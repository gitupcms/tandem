# Tandem: açık kaynak Reflex planı

Tarih: 2026-11-18

## Kaynaklar ve ne aldık

| Kaynak | Ne | Bize faydası |
| --- | --- | --- |
| shopify.engineering/reflex | Mimari yazısı, kod yok. "Share the test, not the code." UI'sız Core, actions-in/state-out ViewModel, JSON introspection node (`name`, `state`, `actions`, `child`), en derindeki node'a odaklanma, navigator'ların `goBack`/`selectTab` ödünç vermesi, NDJSON CLI (`ls`, `do Action [json]`), ağ çağrısında testi düşüren guard, Bun üstünde `precondition`/`do` yardımcıları | Şartname |
| Mevcut açık kaynak uygulama | Çalışan uygulama: protokol, strict decoder, Swift ve Kotlin kit, Python runner, network guard, conformance fixture'ı, 4 skill | Yalnız fikir düzeyinde referans. Hiçbir dosya kopyalanmaz. |
| ivanvanderbyl/skills | `reflex-pattern`: paylaşılan Swift core mimarisi ve `.reflex/` durum defteri (`reflex_state.py`). `duo-pattern` ve `post-deploy-watch` | Yalnız `reflex_state.py` fikri işe yarar. Diğer ikisi konu dışı. |

`.claude/skills` altındaki 7 skill bu iki reponun birebir kopyası.

## Mevcut uygulamanın eksikleri (farkımız bunlar olacak)

1. Swift paketi Linux'ta derlenmiyor (`kit/Sources/ReflexSocketHost/SocketHost.swift:30`), bu yüzden Swift parity yalnız macOS'ta doğrulanıyor.
2. Katkıya kapalı: `AGENTS.md`, `.githooks` ve `check_authors.sh` commit'i yalnız sahibine açıyor. Git geçmişi tek commit.
3. Makaledeki node ağacı, odak, lending ve `@IntrospectionInput` macro'su yerine her aksiyon için elle yazılan adapter var.
4. Test SDK Python runner. Makale Bun/TS `precondition` + `do` (poll, sleep yok) tarif ediyor.
5. Skill'ler `../reflex` kardeş klonuna ve macOS'a bağlı. README'deki "Passed" iddiaları tek ekranlık denemelere dayanıyor.

## Kararlar (2026-11-18'de onaylandı: yeni repo, Bun/TS, farklı isim)

| # | Konu | Önerim | Neden |
| --- | --- | --- | --- |
| K1 | Yaklaşım | Shopify'daki gibi kodu değil testi paylaşmak. `reflex-pattern`'in paylaşılan Swift core yolunu almamak. | Makalenin özü bu. Diğeri ayrı bir proje. |
| K2 | Temel | Yeni repo. Protokol, conformance ve tüm kod sıfırdan yazılır, başka projeden dosya kopyalanmaz. | Telif ve atıf yükü olmaz. Tasarım bize ait. |
| K3 | İsim | **Tandem**. npm paketi `tandem-kit`, Swift `TandemKit`, Kotlin `tandem-kit`. | "Reflex" Shopify'ın adı ve reflex.dev ile çakışıyor. `tandem-kit` npm'de ve GitHub'da boş. |
| K4 | Lisans | MIT (repodaki `LICENSE`) | En az sürtünme. |
| K5 | Araçlar | Uygulama dışında kalan her şey (test SDK, CLI, runner, explore, init) Bun + TypeScript ile yazılır, runtime bağımlılığı olmaz. Python yok. İstisnalar: kitler (Swift, Kotlin) uygulamanın içinde çalıştığı için o dillerde. Network guard `LD_PRELOAD` gerektirdiği için küçük bir C shim'i. | Makaleyle aynı, tek araç zinciri. |
| K6 | Platform | Linux-first (Swift 6 Linux + JVM). iOS simulator ve release-exclusion kontrolü yalnız macOS CI'da. | Bu makine Linux. Core testlerinin cihaz ve macOS gerektirmemesi makalenin vaadi. |

## Fazlar

Her faz bir PR'dır. Faz, doğrulama komutu yeşil olmadan bitmiş sayılmaz.

| Faz | İş | Kim | Çıktı / doğrulama |
| --- | --- | --- | --- |
| F0 | Repo iskeleti, LICENSE, CI, CONTRIBUTING | Ben | **Bitti**, CI yeşil. |
| F1 | Kendi protokolümüz (`spec/protocol.md`: hello/ls/do, node ağacı, odak, lending, kapalı input şeması, kanonik çıktı) ve conformance vakaları, TS referans host ile doğrulanmış | Ben (spec), opus-yazici (vakalar + referans host) | **Bitti**: 86 vaka, TS referans host ile doğrulandı. |
| F2 | Swift kit: strict decoder, `Node` (name/state/actions/child), odak ve lending, NDJSON stdio host. Linux ve macOS. | opus-yazici | **Bitti**: Linux'ta 86/86, diferansiyel fuzz'da TS ve Kotlin ile birebir aynı. |
| F3 | Kotlin kit: aynı yüzey, JVM-only | OpenCode (`/opencode-devret`), takılırsa opus-yazici | **Bitti**: 86/86, Swift ile baytça aynı. |
| F4 | Network guard: `LD_PRELOAD`/`DYLD_INSERT_LIBRARIES` C shim, canary ile | opus-yazici | **Bitti** (Linux): canary reddediliyor ve loglanıyor, iki host guard altında conformance geçiyor. macOS denenmedi. |
| F5 | Bun test SDK: host başlatma, `precondition`, `do`, poll ve son state'i basan hata, `--platform both` parity diff | OpenCode | **Bitti**: `sdk/`, 5 probe journey × (swift, kotlin, parity), bozulan parity'yi yakalayan test. |
| F6 | Örnek uygulama: inventory (liste → detay → artır/azalt, tab + push navigator, GraphQL fixture). Swift Core + Kotlin Core + paylaşılan journey'ler. | OpenCode (Kotlin), opus-yazici (Swift) | ~10 journey, iki platformda yeşil, ağ guard'ı açık |
| F7 | Codegen: Swift `@Introspectable` / `@IntrospectionInput` macro, Kotlin KSP processor, elle yazılan node'ların yerine | opus-yazici | Örnek uygulamada elle yazılmış node kalmaz, testler aynen yeşil |
| F8 | Debug socket host (uygulama içi canlı kullanım), release build'den çıkarıldığının kontrolü. SwiftUI ve Compose örnek host'ları. | opus-yazici | macOS CI'da release binary'de socket sembolü yok |
| F9 | Skill'ler: `start`, `cover`, `check`, `explore` bizim repoya göre yeniden yazılır (kardeş klon yerine paket kurulumu, Linux uyumlu). İsteğe bağlı olarak `reflex_state.py` tarzı ilerleme defteri. `duo-pattern` ve `post-deploy-watch` alınmaz. | Ben | Boş bir test reposunda `/start` → ilk journey yeşil |
| F10 | Dokümanlar (README'de yalnız doğrulanmış iddialar), 0.1.0 sürümü, SPM + Maven Central + npm yayını | Ben + sonnet-okuyucu (doküman/kod tutarlılık denetimi) | Taze klonda README komutları çalışır |

Sıra: F0 → F1 → (F2 ∥ F3) → F4 → F5 → F6 → F7 → F8 → F9 → F10.
MVP F0–F6: makaledeki vaadi uçtan uca kanıtlar.

## Kapsam dışı (şimdilik)

Flutter ve React Native host'ları, `reflex_init.py` tarzı otomatik uygulama tarayıcısı, web hedefi, paylaşılan Swift core (Swift on Android), duo/pane navigasyonu, post-deploy izleme, UI ve piksel doğrulaması.

## Riskler

- Linux'ta Swift macro'ları (F7) swift-syntax sürümüne bağlı. Erken bir spike gerekir.
- Android'de KSP ile Kotlin extension kısıtı yüzünden makaledeki ayrı `…IntrospectionNode` sınıfı gerekebilir.
- iOS tarafı yalnız macOS CI ile doğrulanabilir, yerelde yapılamaz.
- Swift ve Kotlin'in kanonik JSON çıktısını baytça eşitlemek: anahtar sıralama ve string kaçışları için iki dilde de kendi encoder'ımızı yazmak gerekebilir.
