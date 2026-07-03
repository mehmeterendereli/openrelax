# OpenRelax — Hata Düzeltme ve Geliştirme Planı

> Tarih: 2026-07-03 · Kaynak: `openrelax.ps1` (1011 satır) kod incelemesi.
> Öncelik sırası: Faz 1 → Faz 4. Her faz kendi içinde bağımsız commit'lenebilir.
>
> **DURUM: Tüm fazlar v2.0 ile uygulandı (2026-07-03).** Doğrulama: parser temiz,
> `-SelfTest` salt okunur tarama başarılı, GUI smoke testi başarılı.

---

## Tespit Edilen Hatalar

### Kritik

1. **Türkçe karakterler arayüzde bozuk görünüyor (encoding).**
   `openrelax.ps1` BOM'suz UTF-8 olarak kaydedilmiş. `launch.bat` dosyayı Windows PowerShell 5.1 ile çalıştırıyor ve 5.1, BOM'suz dosyayı ANSI okur. Doğrulandı: `"Taranıyor..."` → `"TaranÄ±yor..."` olarak render ediliyor. Bazı metinlerin ASCII'leştirilmiş olması ("Islemci", "Bosalt") bu sorunun daha önce fark edilip yanlış yöntemle geçiştirildiğini gösteriyor.
   **Fix:** Dosyayı UTF-8 with BOM olarak kaydet; ASCII'leştirilmiş tüm metinleri gerçek Türkçe karakterlerle düzelt.

2. **Tüm ağır işlemler UI thread'inde çalışıyor — pencere donuyor.**
   `Scan-Junk`, `Clean-Junk`, `Optimize-RAM` tamamen UI thread'inde. `Get-ChildItem -Recurse` ile `Windows\Logs`, `SoftwareDistribution\Download`, Temp gibi dev klasörler taranıyor; açılışta (scanTimer → Scan-Junk) ve buton tıklamasında pencere "Yanıt Vermiyor" durumuna düşüyor. Koddaki `$form.Invoke(...)` çağrıları arka plan thread niyetini gösteriyor ama hiçbir yerde thread/runspace başlatılmıyor.
   **Fix:** Tarama ve temizliği ayrı bir runspace'te çalıştır, UI güncellemelerini `BeginInvoke` ile yap; işlem sırasında ilerleme göstergesi göster.

3. **Prefetch silmek performansı DÜŞÜRÜR.**
   `Get-JunkPaths` içinde `$env:SystemRoot\Prefetch` temizlik hedefi. Prefetch, Windows'un uygulama açılışlarını hızlandırma mekanizması; silinmesi bir "optimizasyon" aracının amacına ters.
   **Fix:** Prefetch'i listeden tamamen çıkar.

4. **Windows Update indirme önbelleği servis çalışırken siliniyor.**
   `SoftwareDistribution\Download`, `wuauserv` çalışırken silinirse devam eden güncellemeler bozulabilir.
   **Fix:** Ya listeden çıkar, ya da silmeden önce `wuauserv`/`bits` servislerini durdurup sonra yeniden başlat (yalnızca admin modunda).

5. **Auto-Boost her saniye tetikleniyor (thrashing).**
   Timer tick'inde RAM eşik üstündeyse `Optimize-RAM -Silent` çağrılıyor. RAM eşiğin üstünde kaldığı sürece **her saniye** tüm süreçlere `EmptyWorkingSet` uygulanır + her saniye log satırı yazılır. Sayfalar diske itilip geri yüklenir → sistem yavaşlar, tam tersine.
   **Fix:** Cooldown ekle (örn. son boost'tan itibaren en az 5 dk) + histerezis (eşiğin %5 altına inene kadar tekrar tetikleme).

6. **Firefox önbellek temizliği hiç çalışmıyor (yanlış yol).**
   Kod `$env:APPDATA\Mozilla\Firefox\Profiles` (Roaming) altında `cache2` arıyor; `cache2` gerçekte `$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\<profil>\cache2` altındadır.
   **Fix:** Yolu `LOCALAPPDATA`'ya çevir.

### Orta

7. **`Windows\Logs` ve `Panther` silmek riskli.** CBS/DISM logları ve kurulum/rollback bilgileri içerir; sorun tanılamayı imkânsızlaştırır. → Listeden çıkar veya yalnızca X günden eski dosyaları sil.
8. **Eşik ComboBox'ı yazılabilir.** `DropDownStyle` varsayılan `DropDown`; kullanıcı metni silerse `SelectedItem` null → tick içinde exception → boş `catch` yutuyor, Auto-Boost sessizce devre dışı kalıyor. → `DropDownList` yap.
9. **GDI kaynak sızıntıları.** `$form.add_Paint` (satır 94), `$titleBar.add_Paint` (satır 108), `$logPanel.add_Paint` (satır 582) içinde `Pen`/`GraphicsPath` Dispose edilmiyor. Kartlar saniyede bir Invalidate edildiği için birikir. → Tüm Paint handler'larında Dispose.
10. **`Clean-Junk`/`Scan-Junk` gizli dosyaları görmüyor.** `Get-ChildItem`'da `-Force` yok; hidden/system dosyalar ne sayılıyor ne siliniyor → gösterilen boyut eksik. → `-Force` ekle.
11. **Chrome/Edge/Brave/Opera'da yalnızca "Default" profil temizleniyor.** `Profile 1..N` ve `Code Cache`/`GPUCache` kapsam dışı. → Profil klasörlerini glob'la, cache alt tiplerini ekle.
12. **Tarama admin gerektiren yolları sayıyor ama temizleyemiyor.** Kullanıcı "2.3 GB bulundu" görüyor, temizlik sonrası boyut düşmüyor → güven kaybı. → Admin değilken admin gerektiren yolları taramadan da çıkar veya ayrı göster ("1.1 GB için yönetici gerekli").
13. **Çift DNS temizliği + yanıltıcı mesaj.** `Clear-DnsClientCache` hem `Optimize-RAM` hem buton handler'ında; "ağ soketleri temizlendi" mesajı gerçekte yapılmayan bir işi bildiriyor. → Tekilleştir, mesajı düzelt.
14. **`Add-Type -ErrorAction SilentlyContinue` derleme hatasını maskeliyor.** C# derlenemezse `[Win32Helper]` çağrıları anlaşılmaz şekilde patlar. → SilentlyContinue kaldır, hata mesajı göster.
15. **Timer tick'indeki boş `catch` her hatayı yutuyor.** Monitoring sessizce bozulabilir. → En azından ilk hatayı loglayıp devam et.
16. **Kapanışta temizlik yok.** `$timer.Stop()`, `$cpuCounter.Dispose()` yapılmıyor; her tick `Get-Process` tüm süreç nesnelerini açıyor. → FormClosed'da dispose; süreç sayısını `(Get-Process).Count` yerine daha hafif yolla al.
17. **README'de yerel `file:///c:/Users/pc/...` linkleri var.** GitHub'da kırık ve kişisel yol sızdırıyor. → Göreli linke çevir.

### Düşük / Kozmetik

18. **DPI farkındalığı yok** — %125+ ölçekte bulanık görüntü (hardcoded pixel layout).
19. **"Kazanılan RAM" ölçümü yanıltıcı** — `EmptyWorkingSet` sonrası anlık avail farkı; sayfalar geri yüklendikçe kazanım eriyor. Mesaj dilini "geçici olarak boşaltıldı" gibi dürüstleştir.
20. **Sürüm "v1.0" hardcoded** — tek yerde sabit tanımla.
21. **Recycle Bin boyut hesabı** klasör öğelerinde 0 dönebilir — kozmetik tutarsızlık.

---

## Fix ve Geliştirme Planı

### Faz 1 — Kritik düzeltmeler (güvenlik + doğruluk)
- [x] Dosyayı UTF-8 BOM ile kaydet; tüm ASCII'leştirilmiş Türkçe metinleri düzelt (#1)
- [x] `Prefetch`'i temizlik listesinden çıkar (#3)
- [x] `SoftwareDistribution\Download` için servis durdurma koruması veya listeden çıkarma (#4)
- [x] `Windows\Logs` + `Panther`'i çıkar ya da yaş filtresi ekle (#7)
- [x] Firefox cache yolunu `LOCALAPPDATA`'ya düzelt (#6)
- [x] Auto-Boost'a cooldown + histerezis (#5)
- [x] `cmbLimit.DropDownStyle = DropDownList` (#8)
- [x] Yanıltıcı log mesajlarını düzelt, çift DNS temizliğini tekilleştir (#13, #19)

### Faz 2 — Stabilite ve mimari
- [x] Scan/Clean/Optimize'ı arka plan runspace'ine taşı; UI donması bitsin (#2)
- [x] Paint handler'larında Pen/Path/Brush Dispose (#9)
- [x] `Get-ChildItem -Force` + hata sayacı (#10)
- [x] Tüm Chromium profillerini ve cache alt tiplerini kapsa (#11)
- [x] Admin/normal mod yol ayrımı; taramada "yönetici gerekli" ayrımı göster (#12)
- [x] Boş catch'leri logla, `Add-Type` hatasını görünür yap, kapanış cleanup'ı (#14, #15, #16)
- [x] README linklerini düzelt (#17)

### Faz 3 — UX iyileştirmeleri
- [x] Temizlik sırasında ilerleme göstergesi + buton "Temizleniyor..." durumu
- [x] Temizlik kategorileri seçilebilir olsun (checkbox listesi: Temp / Tarayıcı / WU / WER / GPU / Geri Dönüşüm)
- [x] Kategori bazında boyut önizleme (tarama sonucu kategori kırılımı)
- [x] "Yönetici olarak yeniden başlat" butonu (UAC elevation)
- [x] Ayar kalıcılığı: eşik, Auto-Boost durumu, kategori seçimleri → `%APPDATA%\OpenRelax\settings.json`
- [x] Sistem tepsisi (NotifyIcon): kapatınca tray'e küçülme seçeneği — Auto-Boost'un arka planda yaşayabilmesi için
- [x] Uygulama ikonu + Esc ile kapatma + pencere kenarından boyutlandırma kararı

### Faz 4 — Yeni özellikler
- [x] Windows başlangıcında çalıştırma seçeneği (HKCU Run anahtarı, tray modunda)
- [x] TR/EN dil desteği (string tablosu; README zaten iki dilli)
- [x] Temizlik geçmişi: toplam kazanılan alan istatistiği ("Bugüne kadar 12.4 GB temizlendi")
- [x] Zamanlanmış otomatik temizlik (örn. haftada bir, sessiz)
- [x] Disk analiz mini modülü: en çok yer kaplayan 10 klasör (salt okunur rapor)
- [x] DPI-aware manifest / ölçekleme desteği (#18)

---

## Notlar
- `EmptyWorkingSet` tabanlı "RAM optimizasyonu" doğası gereği tartışmalı bir tekniktir; sayfaları diske iter, süreçler onlara tekrar eriştiğinde hard page fault maliyeti doğar. Auto-Boost cooldown'u bu yüzden kritik. Uzun vadede `SetSystemFileCacheSize` / standby list temizliği (admin + `SeProfileSingleProcessPrivilege`) daha dürüst bir alternatif olarak değerlendirilebilir.
- Tek dosya 1000+ satıra ulaştı; Faz 2 sırasında bölgelere ayırmak (UI / cleaning engine / monitoring) bakım maliyetini düşürür ama tek-dosya taşınabilirliği de bir özellik — karar kullanıcıya ait.
