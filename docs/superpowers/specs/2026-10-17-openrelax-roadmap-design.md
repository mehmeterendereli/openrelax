# OpenRelax: geriye dönük kontrol ve geliştirme yol haritası

## Bağlam

**Neden şimdi:** Geliştirme iki hatta bölünmüş ve iki hat birbirinden habersiz.

- **Yerel `main`** (`Masaüstü Arşivi\Eski Araçlar\openrelax`): 2.1.1 LTS → 2.2 → 2.2.1.
  - 18 commit hiç push edilmedi.
  - `v2.1.1-lts`, `v2.2` ve `v2.2.1` etiketleri yalnızca yerelde. GitHub'da sadece `v2.1-lts` var.
- **`origin/main`**: `v2.1-lts`'ten (dea0236) ayrılan 6 PR (#6–#11), "2.1 Preview". İçerdikleri:
  - `lib/OpenRelax.Core.ps1`: atomik/tip doğrulamalı ayarlar, mutex, `Assert-CleanupPath`, reparse koruması, `Invoke-Maintenance`.
  - Hatalı ayarda AutoClean'in durması (fail-closed).
  - Güvenli varsayılanlar: sepet, shader ve WER opt-in; RAM/DNS opt-in.
  - Etkileşimli onay.
  - Fotokapan'da ReaderSid ve korumalı ACL; argümanlar kaydedilmiyor; `-DefenderTrace` opt-in.
  - Erişilebilirlik, TabIndex ve DPI düzeltmeleri.
  - SECURITY, CONTRIBUTING, şablonlar ve CODEOWNERS.
  - SYSTEM/ACL CI testleri, ekran görüntüleri.
- İki hat 44 dosyada +3033/−3261 satır farklı. Düz merge riskli.

**Yerel 2.2.1'de açık kalanlar:**
- `Save-Settings` atomik değil.
- Bozuk ayar sessizce varsayılana dönüyor ve varsayılanda `recycle=true`. Yani haftalık AutoClean sepeti boşaltabilir.
- 28 boş `catch {}` var.

**Kullanım ve dağıtım:**
- Uygulama günlük kullanımda: başlangıçta açılıyor, Auto-Boost %80, 9,4 GB temizlenmiş, Fotokapan kurulu.
- Run anahtarı "Eski Araçlar" yolunu gösteriyor; klasör taşınırsa sessizce kırılır.
- Release, paket ve güncelleme denetimi yok.

**Sağlam olanlar:** `tests/unit.ps1` 43/43, `tests/verify.ps1` temiz.

**Gerçek teşhis:** Son 7 günde 464 sıçrama; `python.exe` ×338, sürücüler ×49, VALORANT ×46. Hangi betik olduğunu ancak komut satırı söyler.

**Kullanıcı kararları:**
1. Taban `origin/main` olacak; 2.2 özellikleri onun üstüne taşınacak (→ **2.3.0**).
2. Komut satırı kaydı **opt-in ayar, varsayılan kapalı** (maskeli).
3. Dört alanın hepsi yol haritasında: Fotokapan, Temizlik, Sağlık, Dağıtım.

**Çıktı:** Tek, push edilmiş, CI'dan geçen bir ana hat ve 2.3 → 2.7 arası sürüm sürüm ilerleyen bir yol haritası.

---

## Genel kurallar (tüm sürümler)

- **Her sürüm bir dal ve bir PR.** CI (`.github/workflows/verify.yml`) geçmeden merge yok. Etiket ve GitHub Release merge'den sonra.
- **Yeni saf mantık `lib/` altına girer:**
  - Mevcut: `lib/OpenRelax.Core.ps1`.
  - Eklenecek: `lib/OpenRelax.Engine.ps1` (walker/kategoriler), `lib/OpenRelax.Trap.ps1` (Fotokapan okuma/teşhis/rapor).
  - Bu modüller worker runspace'lere de enjekte edilir.
  - Her saf fonksiyonun unit testi olur.
- **Arayüz kalıpları origin hattından alınır:** `Fit-ListColumns`, `Set-ListTheme`, `New-EmptyState`, `Set-VisualTabOrder`, accessible adlar, TR/EN string tablosu (`T`).
- **Güvenlik kontratı korunur:** yıkıcı işlemler opt-in, onaylı ve `Assert-CleanupPath`'ten geçer. Yeni temizlik hedefleri safety-contracts testine eklenir.
- **Sürüm sırası:** Tüm sürümler `openrelax.ps1`'e dokunur, bu yüzden **sıralı** yürür (paralel oturum yok). Sıra: 2.3 → 2.4 → 2.5 → 2.6 → 2.7.

---

## 2.3.0: Birleştirme (öncelik 1, diğer her şeyin önkoşulu)

**Dal:** `feat/2.3-reconcile`, `origin/main`'den.

**0. Güvence altına al.**
- Yerel hattı `archive/local-2.2.1` dalı olarak GitHub'a push et.
- Yerel `v2.2`/`v2.2.1` etiketlerini **push etme**. Karışıklık olmasın; yeni hat 2.3.0'dan devam eder.
- `lts/2.1` ve `release/v2.1-lts` dalları yerelde kalır. Origin hattı LTS iddiasını kaldırdı ve bu korunur.

**1. Motor walker'ı.**
- Yerel `Invoke-JunkWalk` (`openrelax.ps1:561`) ile origin'deki `Get-SafeTreeEntries`/`Assert-CleanupPath` (`lib/OpenRelax.Core.ps1:154-196`) tek bir walker'da birleşir.
- Walker'ın davranışı:
  - zaman bütçeli;
  - ilerleme beat'li;
  - junction'a girmez;
  - her silmeden önce yol koruması.
- `Measure-JunkPaths` ve `Remove-JunkPaths` bunu kullanır.
- Hedef dosya: `lib/OpenRelax.Engine.ps1`.

**2. Canlı ilerleme.** Temizlikte dosya/bayt sayacı. Origin'in `Invoke-Maintenance` sonuç modeline (başarılı/kısmi/hata) bağlanır.

**3. Tek geçişli disk analizi.** En fazla 90 sn, alt sınır işareti. Origin'in Disk görünümüne taşınır, `New-EmptyState` kullanır.

**4. Geliştirici önbellekleri (`devcache`).**
- npm, pip, NuGet, Yarn; opt-in; 24 saat kuralı.
- AutoClean izin listesine **eklenmez**. Origin kuralı: AutoClean yalnızca güvenli kategoriler.

**5. RAM hedef seçimi.**
- Yerel `Select-TrimTargets` (`openrelax.ps1:721`): ön plan, 500 ms'de meşgul ve <30 MB süreçler atlanır.
- Origin'in opt-in RAM akışına girer. İmzalı net bellek değişimi raporu korunur.

**6. Fotokapan kaydedici (`fotokapan.ps1`).**
- Origin sürümü taban.
- Ebeveyn komut satırı yeni `-RecordCommandLines` switch'ine bağlanır. Kurulumda ayardan geçer, varsayılan kapalı, `Protect-CommandLine` ile maskeli.
- Defender en çok taranan klasörler, origin'in `-DefenderTrace` opt-in'ine bağlanır.
- 2.2.1 düzeltmesi: boş yollu Defender satırı ve arşiv üyeleri.

**7. Fotokapan arayüzü.**
- Yerel `Get-TrapCategory` (`openrelax.ps1:1118`), `Get-TrapDiagnosis` (`:1151`), `Get-TrapHourHistogram` (`:1200`), `Format-TrapReport` (`:1209`), `Save-TrapReport` (`:1252`) ve `Get-TrapNotification` (`:1262`) taşınır: `lib/OpenRelax.Trap.ps1`.
- Özet ve Kayıtlar sayfaları, Markdown rapor ve tepsi bildirimi origin'in erişilebilir liste/tema kalıplarıyla yeniden kurulur.
- Origin'in "atanmamış CPU, sürücü diye sunulmaz" dürüstlük kuralı teşhis metinlerine uygulanır.

**8. Ayarlar.** Yeni anahtarlar origin'in tip doğrulamalı şemasına eklenir:
- `trapNotify`;
- `trapRecordCommandLines`;
- `categories.devcache`.

Mevcut kullanıcı `settings.json`'ı göç eder: tercihler ve istatistikler korunur.

**9. Testler.**
- Yerel `tests/unit.ps1` (43 test), origin'in `tests/test-support.ps1` yapısına taşınır ve `verify.ps1`'e bağlanır.
- `trap-install.ps1`'in senaryoları `tests/elevated-fotokapan.ps1` ile birleşir; 2.1 düzeninden yükseltme dahil.
- `run-all.ps1` yeniden eklenir.

**10. Belgeler.**
- Sürüm `2.3.0`.
- `CHANGELOG.md`: "Unreleased" + 2.2 notları → 2.3.0.
- `README.md`: TR/EN.
- Bu tasarım `docs/superpowers/specs/` altına yazılır.
- Ayrıntılı uygulama planı `superpowers:writing-plans` ile `docs/superpowers/plans/` altına yazılır.

**11. Yayın.**
- PR → CI yeşil → merge → `v2.3.0` etiketi → GitHub Release.
- Kurulu Fotokapan'ı Fotokapan sekmesinden "Kur / Güncelle" ile yenile.

---

## 2.4: Dağıtım ve kurulum

- **Kurulum.**
  - Origin'deki `install-shortcut.ps1` genişletilip `install.ps1` olur.
  - Dosyaları `%LOCALAPPDATA%\Programs\OpenRelax` altına kopyalar; Başlat menüsü kısayolu oluşturur.
  - Run anahtarını ve haftalık görev yolunu yeni konuma taşır.
  - `-Uninstall` desteği.
- **Yol onarımı.** Açılışta `runAtStartup` açıksa ve Run anahtarı başka bir yolu gösteriyorsa güncel yola yeniden yazılır. Haftalık görev için de aynısı yapılır (`Set-StartupEntry` ve `Set-WeeklyTask`, `openrelax.ps1:904-937`).
- **Release iş akışı.** Etiket push'unda yalnız kaynak dosyalardan zip + `SHA256SUMS` üretilir ve Release'e eklenir.
  - Authenticode imzası sertifika gerektirir. Ayrı karar olarak belgelenir.
- **Scoop manifesti.** Taşınabilir zip ile uyumlu. Winget, imzalı paket gelince değerlendirilir.
- **Güncelleme denetimi.**
  - Opt-in; GitHub Releases API'ye günde en fazla bir istek.
  - Yalnızca bildirir ve Release sayfasını açar. **Otomatik indirip çalıştırmaz.**
- **Toast bildirimleri.** Başlat menüsü kısayolunun AppUserModelID'si ile WinRT toast; mümkün değilse mevcut balon.

## 2.5: Fotokapan derinleştirme

- **Eşik ve süre ayarı arayüzden.**
  - `Threshold`/`SustainSec` yalnız sınırlı değerler alır (70–95 %, 2–10 sn).
  - Görev argümanları yeniden kurulumla güncellenir.
- **Komut satırı içgörüsü.** Kayıt açıksa `python.exe`/`node.exe` vb. için betik yolu çıkarılıp sorumlu olarak gösterilir. Örnek: `python.exe → C:\...\train.py`.
- **Yeni sıçrama türleri.**
  - Disk (`\PhysicalDisk(_Total)\% Idle Time` düşük).
  - Bellek baskısı (`Available MBytes` düşük, sayfa hatası yüksek).
  - GPU (`\GPU Engine(*)\Utilization Percentage`).
  - JSONL kaydında `kind` alanı. Okuyucu eski kayıtlarla uyumlu kalır.
- **Olay Günlüğü korelasyonu.** Sıçrama penceresinde System günlüğünden WHEA, sürücü hataları ve Kernel-Power okunur. Bunlar kanıt olarak eklenir; kesin neden iddia edilmez.
- **Sürücü (DPC) sıçramaları.** Opt-in, yönetici, en fazla 30 sn `wpr` kaydı ve analiz önerisi.
- **Arayüz.**
  - Günlük trend grafiği; mevcut CPU grafiği GDI kalıbı kullanılır, Dispose kurallarıyla.
  - Sorumluya tıklayınca süreç detayı.
  - CSV dışa aktarma.
  - Kayıt saklama süresi ayarı (N ay sonra eski log/jsonl silinir; trap SYSTEM olarak yapar).

## 2.6: Temizlik genişletme

- **Önizleme (dry-run).** Kategori başına en büyük N dosya/klasör listelenir. Walker'ın tarama modu örnek toplar; silme yok.
- **Hariç tutma listesi.** Kullanıcı yolları ve glob'lar. `Assert-CleanupPath` bunları da reddeder; safety-contracts testi eklenir.
- **Yeni hedefler.** Hepsi 24 saat kuralı ve kilitli dosya atlama ile:
  - VS Code: `Cache`, `CachedData`, `GPUCache`, eski loglar;
  - Teams (yeni ve klasik) önbelleği;
  - Steam `htmlcache` ve shader cache;
  - `%LOCALAPPDATA%\CrashDumps`;
  - küçük resim önbelleği (Explorer kilitliyse atlanır);
  - Delivery Optimization (yönetici, `Delete-DeliveryOptimizationCache`).
  - `Windows.old` doğrudan silinmez. Yalnız Disk Temizleme/Storage Sense'i açan bir düğme olur.
- **Ayrıntılı geçmiş.** `%APPDATA%\OpenRelax\history.jsonl`: çalıştırma başına kategori, bayt, dosya ve hata. Arayüzde Geçmiş listesi.
- **CLI.**
  - `-Clean -Categories temp,browser [-WhatIf] [-Json]`.
  - Origin'in exit kodu kontratı: 0 / 1 / 2.
  - Origin'in "SelfTest + AutoClean birlikte reddedilir" kuralı yeni bayraklara da uygulanır.

## 2.7: Sistem sağlığı (yeni "Sağlık" sekmesi; varsayılan salt-okunur)

- **Başlangıç programları.**
  - Kaynaklar: HKCU/HKLM Run, Başlangıç klasörleri, oturum açmada tetiklenen görevler.
  - Aç/kapa, Görev Yöneticisi'nin kullandığı `StartupApproved` kayıtlarıyla yapılır. Geri alınabilir, silme yok.
- **Disk sağlığı.**
  - `Get-PhysicalDisk` HealthStatus.
  - Yönetici ise `Get-StorageReliabilityCounter`: sıcaklık, aşınma, okuma hataları.
- **Pil.** `powercfg /batteryreport /xml` ayrıştırılır: tasarım ve tam şarj kapasitesi, aşınma yüzdesi.
- **Büyük dosya bulucu.** Disk walker'ı yeniden kullanır; profilde 500 MB üstü en büyük 50 dosya. Salt-okunur; "Klasörde göster" düğmesi.
- **Sağlık raporu.** `Save-TrapReport` kalıbıyla Markdown, `Belgeler\OpenRelax\` altına.

---

## Kritik dosyalar

- `openrelax.ps1`: arayüz, worker'lar ve modlar. Origin'de 3222 satır, yerelde 3459.
- `lib/OpenRelax.Core.ps1`: origin'den gelen; ayarlar, yol korumaları, `Invoke-Maintenance`.
- `lib/OpenRelax.Engine.ps1`, `lib/OpenRelax.Trap.ps1`: yeni; yerel saf fonksiyonların taşındığı yer.
- `fotokapan.ps1`: kaydedici ve kurulum (origin tabanı).
- `tests/verify.ps1`, `tests/test-support.ps1`, `tests/safety-contracts.ps1`, `tests/elevated-fotokapan.ps1`; yerel `tests/unit.ps1` taşınacak.
- `.github/workflows/verify.yml`; 2.4'te release iş akışı eklenecek.
- `CHANGELOG.md`, `README.md`, `PLAN.md`.

## Doğrulama

- **Her PR'da:**
  - `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\verify.ps1`: parser, salt-okunur SelfTest, safety contracts ve unit testler.
  - Ardından GitHub Actions'ın yeşil olması.
- **2.3 kabulü:**
  1. Taşınan 43 unit testin hepsi ve origin'in 17 safety-contract testi geçer.
  2. `engine-stress.ps1` ve `gui-stress.ps1`: GDI/handle büyümesi yok.
  3. `elevated-fotokapan.ps1` yönetici olarak: 2.2.1 kurulumundan yükseltme; ACL korumalı.
  4. Gerçek `settings.json` göçü, kopya bir `%APPDATA%` üzerinde denenir: tercihler ve 9,4 GB istatistiği korunur.
  5. Elle arayüz turu: TR/EN, dört sekme ve Fotokapan Özet/Kayıtlar sayfaları.
  6. Komut satırı ayarı açılınca yeni kayıtlarda maskeli `cmd` alanı görünür; kapalıyken görünmez.
- **Sonraki sürümler:** Her yeni hedef veya özellik unit + safety-contract testiyle gelir. Yıkıcı testler yalnızca sahibi doğrulanmış sentetik fixture'larda koşar; gerçek profilde değil.

## Uygulama başlangıcı

Plan onaylanınca:
1. `superpowers:writing-plans` ile 2.3.0'ın görev görev uygulama planı yazılır.
2. `feat/2.3-reconcile` dalında adım 0'dan başlanır. İlk iş: yerel hattı `archive/local-2.2.1` olarak push etmek; bunun için ayrıca onay istenir.
