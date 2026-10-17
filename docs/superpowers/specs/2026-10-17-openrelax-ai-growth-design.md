# OpenRelax: AI çağı ve büyüme planı

> Tarih: 2026-10-17. Önceki yol haritası: `2026-10-17-openrelax-roadmap-design.md`.
> Bu belge 2.4 ve sonrasının sırasını yeniden belirler.

## 1. Hedef

İnsanların gerçekten kullanıp fayda göreceği bir Windows bakım aracı. Üç vaadi var:

1. **PC'yi yormaz.** Ölçülmüş ve README'de yayınlanmış tüketim rakamlarıyla.
2. **Ne olduğunu kaydeder.** Fotokapan, uygulama açıkken arka planda CPU sıçramalarının sorumlusunu yakalar.
3. **AI asistanınıza anlatır.** OpenRelax bir MCP sunucusu sunar. Claude Desktop, Claude Code, Cursor ya da başka bir MCP istemcisi "PC'm neden yavaş?" sorusunu OpenRelax'ın kayıtlarına dayanarak cevaplar.

Uygulamanın içine bir dil modeli ya da API anahtarı **konmaz** ("kendi AI'nı getir"). Uygulama hafif, ücretsiz ve çevrimdışı kalır. AI, kullanıcının zaten kullandığı asistandır.

**Başarı ölçütleri:**

- **3 ay sonunda:**
  - 2.5 (MCP) yayımlanmış.
  - Resmî MCP Registry'de ve `punkpeye/awesome-mcp-servers`'ta listelenmiş.
  - En az 500 GitHub yıldızı.
  - En az 10 harici issue veya PR.
- **6 ay sonunda:** 1 500+ yıldız ve Scoop ya da winget ile tek komutla kurulum.

## 2. Rakip tablosu (GitHub API, 17.10.2026)

| Repo | Yıldız | Dil | Ne yapar | OpenRelax'tan farkı |
| --- | ---: | --- | --- | --- |
| ChrisTitusTech/winutil | 64 396 | PowerShell | Program kurulumu, tweak, düzeltme | Neden yavaş olduğunu söylemez; kullanıcının ne yapacağını bilmesini bekler |
| Raphire/Win11Debloat | 59 468 | PowerShell | Hazır uygulama ve telemetri kaldırma | Tek seferlik; izleme yok |
| qarmin/czkawka | 34 311 | Rust | Kopya ve boş dosya bulucu | Farklı alan |
| BCUninstaller | 21 907 | C# | Toplu program kaldırma | Farklı alan |
| hellzerg/optimizer | 18 239 | C# | Optimizasyon | **Arşivlendi** (2026-01); kullanıcıları boşta |
| winsiderss/systeminformer | 16 260 | C | Ayrıntılı süreç izleme | Uzmanlara yönelik; geçmiş ya da açıklama yok |
| farag2/Sophia-Script | 9 799 | PowerShell | İnce ayar modülü | Teşhis yok |
| CursorTouch/Windows-MCP | 9 353 | Python | AI'ın Windows'u fareyle kullanması | Bakım ya da teşhis değil; Windows + MCP talebinin kanıtı |
| bleachbit/bleachbit | 7 139 | Python | Dosya temizleyici | Yalnız temizlik |
| Ashfaqbs/SystemMind | 3 | Python | MCP ile sistem teşhisi | Ham ve küçük; doğrudan rakip ama boşluk açık |
| mehmeterendereli/openrelax | 1 | PowerShell | — | — |

Ticari ve kapalı tarafta Microsoft Copilot "PC Insights" Insider'da. Yalnız **o anki** durumu teşhis ediyor, değişiklik yapmıyor ve kayıt geçmişi yok. Settings agent şimdilik İngilizce ve yalnız Copilot+ PC'lerde.

**Çıkarımlar:**

- PowerShell ile 60 bin yıldıza ulaşmak mümkün (WinUtil, Win11Debloat). Dil engel değil.
- "Geçmişi kaydeden ve AI'ya anlatan bakım aracı" alanı boş. SystemMind dışında açık kaynak bir örnek yok.
- Optimizer'ın arşivlenmesiyle 18 bin yıldızlık bir kitle yeni bir araç arıyor.

## 3. Ürün kararları

### 3.1 Gömülü Fotokapan (2.4)

**Kullanıcı kararı:** Fotokapan ayrı bir uygulama ya da SYSTEM görevi olmayacak. OpenRelax açıkken (tepside) arka planda çalışacak; kullanıcı tek anahtarla açıp kapatacak.

**Ölçümler (bu makinede, yönetici değil):**

| Yöntem | Örnek başına CPU | Defender (MsMpEng) | Yönetici gerekir mi |
| --- | ---: | --- | --- |
| Bugünkü: `Process.TotalProcessorTime`, tüm süreçler | ~300 ms | Okunamıyor (boş) | Evet (SYSTEM) |
| **PDH `Process` kategorisi, `ReadCategory()` tek çağrı** | **~16 ms** | **Okunuyor** (428 sürecin hepsi, PID'leriyle) | **Hayır** |

İlk çağrı ~700 ms sürüyor (ısınma); sonraki çağrılar 20 ms'nin altında. OpenRelax'ın kendi ayak izi: tepsideyken 125 MB özel bellek; 39 dakikada 3,3 sn CPU, yani tek çekirdeğin ~%0,14'ü.

**Tasarım:**

- **Örnekleyici.** Ayrı bir runspace'te çalışır. UI iş parçacığı meşgul olsa bile örnekler; iş parçacığı önceliği AboveNormal.
- **Sakin durum.** 2 saniyede bir yalnızca `Processor(_Total)\% Processor Time`, `% DPC Time` ve `% Interrupt Time` okunur. Bu çok ucuzdur.
- **Sıçrama.** Eşik aşıldığı ilk anda `Process` kategorisinin anlık görüntüsü alınır, sıçrama süresince tekrarlanır. Mevcut "sıçramanın kendisini ölç" mantığı korunur.
- **Sürücü kanıtı.** `% DPC Time` ve `% Interrupt Time` doğrudan ölçülür. "Atanamayan CPU" artık ikiye ayrılır: *sürücü (DPC/kesme, ölçülmüş)* ve *açıklanamayan*. Böylece eski "sürücü" teşhisi bu kez kanıta dayanarak geri gelir.
- **Ebeveyn ve komut satırı.** CIM `Win32_Process` ile alınır. Yönetici değilken komut satırı yalnız kullanıcının kendi süreçleri için okunur. `python.exe` gibi asıl hedefler zaten kullanıcının süreçleri. Maskeleme ve opt-in kuralı aynen kalır.
- **Veri.** `%APPDATA%\OpenRelax\Fotokapan\`. Aynı JSONL sözleşmesi (`spikes-YYYY-MM.jsonl`, `durum.json`) kullanılır; böylece teşhis, rapor ve bildirim kodu (`lib/OpenRelax.Trap.ps1`) değişmeden çalışır. Dosyalar kullanıcının kendi profilinde olduğu için SYSTEM ACL karmaşası kalkar.
- **Ayar.** `trapEnabled` (varsayılan **açık**, ilk açılışta tek satırlık bilgi notu). Mevcut ayarlardaki `trapNotify` ve `trapRecordCommandLines` aynen kullanılır.
- **Geçiş.**
  - 2.4 açılışta eski SYSTEM görevini algılar ve "Eski arka plan görevini kaldır" önerir; kaldırma tek UAC onayı ister.
  - Eski `ProgramData` kayıtlarını salt-okunur olarak birlikte okur; geçmiş kaybolmaz.
  - `fotokapan.ps1` 2.4'te yalnızca `-Uninstall` için kalır, 2.5'te repodan çıkar.
- **Kabul edilen sınırlar.**
  - Uygulama kapalıyken kayıt yok (kullanıcı kararı).
  - Defender tarama türü tespiti Operational günlüğünü okuyabilmeye bağlı. Yönetici değilken okunamazsa "Defender" kategorisi tarama/gerçek zamanlı ayrımı yapılmadan gösterilir.

**Testler.**

- Sentetik CPU yüküyle (mevcut `fotokapan-stress.ps1` kalıbı) uygulama içi örnekleyici doğrulanır: sıçrama yakalanmalı, doğru süreç atanmalı, örnekleyici tek çekirdeğin %1'inden azını tüketmeli.
- Kullanıcının canlı istatistiklerini kirletmemesi için test, ayrı bir `-TestMode` veri klasörüne yazar.

### 3.2 Hafiflik kanıtı (2.4)

- `tests/footprint.ps1`: uygulamayı tepside 10 dakika çalıştırır; CPU, bellek, handle ve GDI ölçer. README'de "Ölçülmüş tüketim" tablosu olarak yayımlanır.
- Hedefler:
  - boşta tek çekirdeğin %0,3'ünden az;
  - Fotokapan açıkken sakin durumda %1'den az;
  - 30 dakikada bellek büyümesi 20 MB'tan az.
- 125 MB'lık PowerShell + WinForms tabanı bilinen bir sınır. İddia "en az RAM" değil, "**arka planda neredeyse sıfır CPU**" olarak kurulur. Native bir yeniden yazım ancak kullanıcı talebi gelirse ayrı karar olur.

### 3.3 MCP sunucusu (2.5)

- **Dosya:** `openrelax-mcp.ps1`. Bağımlılıksız; Windows PowerShell 5.1 ile stdio üzerinden JSON-RPC konuşur.
  - Protokol 2025-11-25; istemci daha eskiyse 2025-06-18 ve 2025-03-26 ile pazarlık yapar.
  - stdout yalnız protokol mesajları içindir; günlükler stderr'e gider.
- **Kod.** `lib/OpenRelax.*.ps1` dosyalarını dot-source eder. GUI'nin çalışıyor olması gerekmez; Fotokapan verisini dosyadan okur.
- **Araçlar.** Hepsi `annotations` ile işaretlenir.

| Araç | Tür | Ne döner |
| --- | --- | --- |
| `get_system_snapshot` | salt-okunur | CPU/RAM/disk/uptime, en çok tüketen 10 süreç |
| `get_spike_history` (`days` ≤ 30) | salt-okunur | Bölümler: zaman, süre, tepe, sorumlu, notlar |
| `diagnose_slowness` | salt-okunur | `Get-TrapDiagnosis` bulguları + anlık durum + tavsiye anahtarları |
| `scan_junk` | salt-okunur | Kategori başına boyut (SelfTest motoru) |
| `analyze_disk` | salt-okunur | Profilde en büyük 10 klasör |
| `get_report` | salt-okunur | Markdown teşhis raporu |
| `clean_junk` (`categories`, `confirm`) | **yıkıcı** (`destructiveHint`) | Yalnız GUI'deki onaylı yolun izin verdiği kategoriler; `confirm:true` olmadan ya da istemci elicitation destekliyorsa kullanıcı onayı olmadan çalışmaz; sepet ve Windows Update yalnız GUI'den |

- **Gizlilik.** Komut satırları yalnız opt-in açıksa ve maskelenmiş olarak döner. Kullanıcı adı ve profil yolu `%USERPROFILE%` olarak gösterilir.
- **Kurulum kolaylığı.**
  - Ayarlar'da **"AI asistanına bağla"** düğmesi `%APPDATA%\Claude\claude_desktop_config.json` dosyasına `openrelax` girdisini ekler; önce yedek alınır, mevcut girdiler korunur.
  - README'ye Claude Code (`claude mcp add openrelax -- powershell -NoProfile -File …\openrelax-mcp.ps1`), Cursor ve VS Code örnekleri eklenir.
- **Listeleme.**
  - Resmî MCP Registry: `server.json` dosyası, GitHub ile ad alanı doğrulaması; önce initialize el sıkışması doğrulanır.
  - `punkpeye/awesome-mcp-servers` (96 bin yıldız), Glama ve Smithery dizinleri.
- **Testler.** `tests/mcp-contract.ps1` sunucuyu alt süreç olarak başlatır ve şunları doğrular:
  - `initialize`, `tools/list` ve araç çağrıları;
  - yıkıcı aracın `confirm` olmadan reddedildiği;
  - stdout'a protokol dışı tek satır yazılmadığı.

### 3.4 Uygulama içi "Neden yavaş?" (2.5, LLM'siz)

Fotokapan özetinin başına tek cümlelik, kural tabanlı bir özet eklenir. Örnek: "Son 7 günde yükün %74'ü python.exe'den; çoğu 21:00–23:00 arası." Yanına bir **"AI asistanına sor"** düğmesi konur; MCP bağlıysa hazır soruyu panoya kopyalar ve kısa bir rehber gösterir.

## 4. Görünürlük ve büyüme planı

### 4.1 Hazırlık (2.5 kodlanırken paralel)

- **README baştan yazılır (İngilizce önce, Türkçe bölüm korunur).**
  - İlk ekran 3 saniyede anlaşılmalı: "Finds what slowed your PC down while you weren't looking — and explains it to your AI assistant."
  - Hero GIF (≤ 60 sn): bir CPU sıçraması olur, Fotokapan yakalar, Claude'a "PC'm neden yavaştı?" diye sorulur, cevap gelir.
  - Rakip karşılaştırma tablosu (özellik bazında, saygılı dil), ölçülmüş tüketim tablosu, tek satır kurulum, güvenlik sözleşmesi özeti.
- **GitHub ayarları.**
  - Topic'ler: `windows`, `mcp`, `mcp-server`, `pc-optimization`, `powershell`, `performance`, `cpu-monitor`, `claude`, `ai-tools`.
  - Sosyal önizleme görselinin yenilenmesi.
  - Discussions'ın açılması.
  - 5–10 adet `good first issue` (dil çevirileri, yeni temizlik hedefleri, MCP istemci örnekleri).
- **Dağıtım.**
  - Release'e imzasız ama SHA256'lı zip.
  - Scoop manifesti.
  - `irm https://… | iex` tek satırlık kurulum (WinUtil modeli): betik indirmeden önce sürüm ve SHA256 doğrular ve ne yaptığını ekrana yazar.
- **İçerik.** Lansmandan 2–3 gün önce bir teknik yazı yayımlanır: "Windows'ta CPU sıçramasını yönetici yetkisi olmadan yakalamak: 300 ms'den 16 ms'ye" (dev.to + Medium, Türkçe sürümü Technopat veya kişisel blog). Yazı lansmandan önce dizinlenmiş olur.

### 4.2 Lansman sırası

| Gün | Kanal | Açı |
| --- | --- | --- |
| T0 (Salı/Çarşamba, 08:00–09:00 ET = 15:00–16:00 TSİ) | Hacker News ("Show HN: OpenRelax – …") | Teknik hikâye + MCP |
| T0 | r/opensource | Açık kaynak, güvenlik sözleşmesi |
| T+1 | r/ClaudeAI, r/mcp | MCP sunucusu, demo GIF |
| T+2 | r/PowerShell | 16 ms PDH tekniği, bağımlılıksız MCP sunucusu |
| T+3 | r/Windows11, r/pcmasterrace | "Oyunum neden takılıyor?" senaryosu (VALORANT örneği) |
| T+4 | Türkiye: Technopat, DonanımHaber, r/CodingTR, LinkedIn | Türkçe arayüz, yerli proje |
| T+14 | Product Hunt (isteğe bağlı) | Toplu sonuçlarla |

**Kurallar:**

- Her alt forumun kenar çubuğu ve sabit kuralları gönderiden önce okunur; gerekirse moderatöre önceden yazılır.
- Hesapta 90/10 katılım/tanıtım oranı korunur; lansmandan önce bu forumlarda gerçekten yardım edilir.
- Başlık "I made …" biçiminde olur; sınırlar dürüstçe yazılır (imzasız, PowerShell, uygulama kapalıyken kayıt yok).
- İlk 24 saatte her yoruma cevap verilir.
- Yıldız istemek, yıldız takası ya da sahte hesap **yasak**.

Kaynakların gösterdiği beklenti: HN'de görünürlük elde eden AI araçları ilk haftada ortalama ~289 yıldız aldı. Etkiyi zamanlama "Show HN" etiketinden daha çok belirliyor. Reddit, açık kaynak geliştirici araçları için ana kanallardan biri.

### 4.3 Sonrası

- İlk iki hafta günlük; sonra haftalık olarak yıldız, ziyaret, klon, issue, MCP kurulum sayısı izlenir.
- Gelen her issue'ya 48 saat içinde cevap verilir.
- Ayda bir sürüm çıkarılır ve sürüm notu her kanalda kısa bir güncellemeyle paylaşılır.
- En çok istenen 3 özellik bir sonraki sürüme alınır.

## 5. Güncellenmiş sürüm sırası

| Sürüm | İçerik |
| --- | --- |
| **2.4** | Gömülü Fotokapan (PDH örnekleyici, DPC/kesme kanıtı, `trapEnabled`, eski görevin kaldırılması ve kayıtların okunması); `tests/footprint.ps1` ve README ölçümleri; Release zip + SHA256 + Scoop; başlangıç yolu onarımı |
| **2.5** | `openrelax-mcp.ps1` + "AI asistanına bağla" düğmesi + `tests/mcp-contract.ps1`; uygulama içi "Neden yavaş?" özeti; MCP Registry ve awesome-list başvuruları |
| **Lansman** | 2.5 yayımlandıktan sonra §4.2 takvimi; README, GIF ve yazı 2.5 ile paralel hazırlanır |
| 2.6+ | Önceki yol haritasındaki temizlik genişletme (önizleme, hariç tutma, yeni hedefler, CLI) ve sistem sağlığı sekmesi; öncelikler lansman geri bildirimine göre sıralanır |

## 6. Riskler

- **İmzasız PowerShell betiği.** SmartScreen ve AV uyarıları güveni düşürür. Önlem: SHA256, kaynak dağıtımı, açık güvenlik sözleşmesi; uzun vadede imza.
- **`irm | iex` kurulumu.** Bir kesim buna güvenmez. Zip ve Scoop alternatif olarak her zaman sunulur.
- **Yıkıcı MCP aracı.** AI'ın yanlış yorumu riski var. Önlem: yalnız güvenli kategoriler, `confirm` ve elicitation, GUI'deki aynı `Assert-CleanupPath` korumaları.
- **AI uydurması.** Araçlar yalnız ölçülmüş veri döndürür; uygulama AI'dan gelen serbest komutları hiçbir zaman çalıştırmaz.
- **Reddit yasakları.** Kurallara uyum, 90/10, moderatöre önceden yazmak.
- **Tek bakımcı.** Lansman sonrası issue yükü. Önlem: şablonlar, `good first issue`, net CONTRIBUTING.

## 7. Kaynaklar

- Rakip verileri: GitHub REST API, 17.10.2026.
- Copilot PC Insights: [thewincentral](https://thewincentral.com/windows-11-copilot-pc-insights-ai-performance-diagnostics/), [eastleighvoice](https://eastleighvoice.co.ke/technology/378788/microsoft-tests-ai-tool-that-can-diagnose-why-your-windows-11-pc-is-running-slow), [beebom](https://beebom.com/ai-agent-comes-to-windows-settings-rolling-out-to-copilot-plus-pcs/amp/)
- MCP sürümleri: [modelcontextprotocol.io changelog](https://modelcontextprotocol.io/specification/2025-06-18/changelog), [chatforest](https://chatforest.com/guides/mcp-versioning-backward-compatibility/)
- MCP Registry: [roxyapi](https://roxyapi.com/blogs/mcp-registries-where-to-list-your-server-2026), [dev.to](https://dev.to/amareswer/the-mcp-registry-by-the-numbers-38nc)
- Lansman verisi: [arXiv 2511.04453](https://arxiv.org/abs/2511.04453v1), [Infisical](https://infisical.com/blog/how-we-got-3000-github-stars-in-2-months.md), [alexcloudstar](https://alexcloudstar.com/blog/open-source-growth-strategy-developers-2026)
- Reddit kuralları: [redship](https://redship.io/blog/reddit-self-promotion-rules-2026)
- SystemMind: [GitHub](https://github.com/ashfaqbs/systemmind)
