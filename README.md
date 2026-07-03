# OpenRelax PC Care 🚀

**OpenRelax** is a lightweight, safe, and beautiful open-source Windows system optimization utility built with PowerShell and Windows Forms — a single script, no installation. It reclaims RAM, cleans application/browser caches, and stays out of your way in the system tray.

---

## Özellikler / Features

### 🇹🇷 Türkçe
- **Tek Tıkla Sistem Bakımı:** Seçili kategorilerdeki tüm temizlik ve RAM optimizasyonu tek butonla, arka planda çalışır — arayüz asla donmaz.
- **Seçilebilir Temizlik Kategorileri:** Geçici dosyalar, tarayıcı önbellekleri (Chrome, Edge, Brave, Opera/Opera GX, Firefox — tüm profiller), Discord, GPU shader önbellekleri, Windows hata raporları (WER), Windows Update önbelleği, GPU kurulum kalıntıları ve Geri Dönüşüm Kutusu. Her kategori Ayarlar sekmesinden açılıp kapatılabilir.
- **Güvenli RAM Optimizasyonu:** Native Windows API'leri ile süreçlerin kullanmadığı fiziksel bellek geri kazanılır; kritik sistem süreçleri asla dokunulmaz.
- **Akıllı Oto RAM Boşaltma:** RAM belirlediğiniz eşiği aşınca otomatik temizlik — 5 dakikalık bekleme süresi ve histerezis ile sistemi yormadan.
- **Sistem Tepsisi:** Pencereyi kapatınca uygulama tepside yaşamaya devam eder (ayarlardan kapatılabilir); tepsiden tek tıkla bakım yapılabilir.
- **Windows ile Başlatma & Haftalık Otomatik Temizlik:** Ayarlardan tek tikle etkinleştirilir.
- **Disk Analizi:** Kullanıcı profilinizdeki en büyük 10 klasörü gösterir (salt okunur).
- **İstatistikler:** Bugüne kadar toplam temizlenen alan ve bakım sayısı kaydedilir.
- **TR / EN Dil Desteği** ve gerçek zamanlı CPU/RAM/uptime monitörü.

### 🇺🇸 English
- **One-Click Maintenance:** All cleanup and RAM optimization runs on a background thread — the UI never freezes.
- **Selectable Cleanup Categories:** Temp files, browser caches (Chrome, Edge, Brave, Opera/Opera GX, Firefox — all profiles), Discord, GPU shader caches, Windows Error Reporting, Windows Update cache, GPU installer leftovers, and the Recycle Bin. Toggle each category in Settings.
- **Safe RAM Optimization:** Uses native Windows APIs to trim idle working sets; critical system processes are never touched.
- **Smart Auto-Boost:** Automatically trims RAM when usage crosses your threshold — with a 5-minute cooldown and hysteresis so it never thrashes your system.
- **System Tray:** Closing the window keeps OpenRelax alive in the tray (optional); run maintenance straight from the tray menu.
- **Run at Startup & Weekly Scheduled Cleanup:** One checkbox each in Settings.
- **Disk Analysis:** Shows the 10 largest folders in your user profile (read-only).
- **Statistics:** Tracks total space cleaned and maintenance runs over time.
- **TR / EN language support** plus a real-time CPU/RAM/uptime monitor.

---

## Nasıl Çalıştırılır? / How to Run

1. Double-click **[launch.bat](launch.bat)** — the console window closes itself and the dark-themed OpenRelax window opens.
2. Optional command-line modes for [openrelax.ps1](openrelax.ps1):
   - `-StartMinimized` — start hidden in the system tray (used by the startup entry)
   - `-AutoClean` — headless cleanup using your saved settings (used by the weekly scheduled task)
   - `-SelfTest` — read-only scan that prints what would be cleaned, without deleting anything

Settings are stored in `%APPDATA%\OpenRelax\settings.json`.

---

## Güvenlik Felsefesi / Safety Philosophy

OpenRelax deliberately does **not** clean:

- `Windows\Prefetch` — deleting it *slows down* app launches; Windows manages it itself.
- `Windows\Logs` & `Panther` — needed for diagnostics and upgrade rollback.
- Browser profiles/bookmarks/history — only regenerable cache directories are targeted.

The Windows Update cache is cleaned only when running as Administrator, and only after temporarily stopping the update services (they are restarted afterwards). Locked or in-use files are always skipped silently.

---

## Lisans / License

This project is licensed under the MIT License.
