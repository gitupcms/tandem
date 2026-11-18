// Test canary for guard.test.ts: prints "<check> <rc> <errno>" per network attempt.
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static struct sockaddr_in addr(const char *ip, int port) {
  struct sockaddr_in a = {0};
  a.sin_family = AF_INET;
  a.sin_port = htons(port);
  inet_pton(AF_INET, ip, &a.sin_addr);
  return a;
}

int main(void) {
  struct timeval tv = {2, 0}; // unguarded runs may have no network: bound the connect wait
  int s = socket(AF_INET, SOCK_STREAM, 0);
  setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
  struct sockaddr_in a = addr("1.1.1.1", 80);
  errno = 0;
  int rc = connect(s, (struct sockaddr *)&a, sizeof a);
  printf("tcp %d %d\n", rc, errno);
  close(s);

  s = socket(AF_INET, SOCK_DGRAM, 0);
  a = addr("8.8.8.8", 53);
  errno = 0;
  rc = (int)sendto(s, "x", 1, 0, (struct sockaddr *)&a, sizeof a);
  printf("udp %d %d\n", rc, errno);
  close(s);

  int l = socket(AF_INET, SOCK_STREAM, 0);
  a = addr("127.0.0.1", 0);
  socklen_t len = sizeof a;
  bind(l, (struct sockaddr *)&a, sizeof a);
  listen(l, 1);
  getsockname(l, (struct sockaddr *)&a, &len);
  s = socket(AF_INET, SOCK_STREAM, 0);
  errno = 0;
  rc = connect(s, (struct sockaddr *)&a, sizeof a);
  printf("loopback %d %d\n", rc, errno);
  printf("ECONNREFUSED %d\n", ECONNREFUSED);
  return 0;
}
