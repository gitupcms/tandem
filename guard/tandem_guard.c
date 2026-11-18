// Tandem network guard: refuses and logs non-loopback AF_INET/AF_INET6 connect/sendto/sendmsg.
// Contract: .orkestra/guard-sozlesme.md. Linux: LD_PRELOAD. macOS: DYLD_INSERT_LIBRARIES (__interpose).
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#ifndef __APPLE__
#include <dlfcn.h>
#endif

static void log_line(const char *line) {
  int saved = errno;
  const char *path = getenv("TANDEM_GUARD_LOG");
  int fd = (path && *path) ? open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644) : 2;
  if (fd >= 0) {
    ssize_t r = write(fd, line, strlen(line)); // one write per line: O_APPEND keeps lines whole across processes
    (void)r;
    if (fd != 2) close(fd);
  }
  errno = saved;
}

__attribute__((constructor)) static void tandem_guard_loaded(void) {
  char line[64];
  snprintf(line, sizeof line, "loaded %d\n", (int)getpid());
  log_line(line);
}

// Returns 1 (and logs) when the destination must be refused.
static int deny(const struct sockaddr *sa, socklen_t len) {
  if (!sa) return 0;
  char addr[INET6_ADDRSTRLEN], line[128];
  if (sa->sa_family == AF_INET && len >= (socklen_t)sizeof(struct sockaddr_in)) {
    const struct sockaddr_in *in = (const struct sockaddr_in *)sa;
    if ((ntohl(in->sin_addr.s_addr) >> 24) == 127) return 0;
    inet_ntop(AF_INET, &in->sin_addr, addr, sizeof addr);
    snprintf(line, sizeof line, "denied ipv4 %s %u\n", addr, ntohs(in->sin_port));
  } else if (sa->sa_family == AF_INET6 && len >= (socklen_t)sizeof(struct sockaddr_in6)) {
    const struct sockaddr_in6 *in6 = (const struct sockaddr_in6 *)sa;
    const struct in6_addr *a = &in6->sin6_addr;
    if (IN6_IS_ADDR_LOOPBACK(a)) return 0;
    if (IN6_IS_ADDR_V4MAPPED(a) && a->s6_addr[12] == 127) return 0; // ::ffff:127.x.y.z (dual-stack JVM sockets)
    inet_ntop(AF_INET6, a, addr, sizeof addr);
    snprintf(line, sizeof line, "denied ipv6 %s %u\n", addr, ntohs(in6->sin6_port));
  } else {
    return 0; // AF_UNIX, AF_UNSPEC, other families pass
  }
  log_line(line);
  return 1;
}

#ifdef __APPLE__
// Inside the interposing image, calls to connect/sendto/sendmsg reach the originals.
static int g_connect(int fd, const struct sockaddr *sa, socklen_t len) {
  if (deny(sa, len)) { errno = ECONNREFUSED; return -1; }
  return connect(fd, sa, len);
}
static ssize_t g_sendto(int fd, const void *buf, size_t n, int flags, const struct sockaddr *sa, socklen_t len) {
  if (deny(sa, len)) { errno = ECONNREFUSED; return -1; }
  return sendto(fd, buf, n, flags, sa, len);
}
static ssize_t g_sendmsg(int fd, const struct msghdr *msg, int flags) {
  if (msg && deny((const struct sockaddr *)msg->msg_name, msg->msg_namelen)) { errno = ECONNREFUSED; return -1; }
  return sendmsg(fd, msg, flags);
}
#define INTERPOSE(repl, orig) \
  __attribute__((used)) static const struct { const void *r, *o; } interpose_##orig \
  __attribute__((section("__DATA,__interpose"))) = { (const void *)repl, (const void *)orig }
INTERPOSE(g_connect, connect);
INTERPOSE(g_sendto, sendto);
INTERPOSE(g_sendmsg, sendmsg);
#else
#define REAL(name) static __typeof__(name) *real; if (!real) real = (__typeof__(name) *)dlsym(RTLD_NEXT, #name)

int connect(int fd, const struct sockaddr *sa, socklen_t len) {
  REAL(connect);
  if (deny(sa, len)) { errno = ECONNREFUSED; return -1; }
  return real(fd, sa, len);
}
ssize_t sendto(int fd, const void *buf, size_t n, int flags, const struct sockaddr *sa, socklen_t len) {
  REAL(sendto);
  if (deny(sa, len)) { errno = ECONNREFUSED; return -1; }
  return real(fd, buf, n, flags, sa, len);
}
ssize_t sendmsg(int fd, const struct msghdr *msg, int flags) {
  REAL(sendmsg);
  if (msg && deny((const struct sockaddr *)msg->msg_name, msg->msg_namelen)) { errno = ECONNREFUSED; return -1; }
  return real(fd, msg, flags);
}
#endif
