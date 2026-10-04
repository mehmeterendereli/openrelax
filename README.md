# OpenRelax PC Care 🚀

**OpenRelax** is a lightweight, safe, and beautiful open-source Windows system optimization utility built with PowerShell and Windows Forms — a single script, no installation. It reclaims RAM, cleans application/browser caches, records who causes CPU spikes, and stays out of your way in the system tray.

**Sürüm / Version: 2.1 LTS** — see [CHANGELOG.md](CHANGELOG.md).

---

## Özellikler / Features

### 🇹🇷 Türkçe
- **Tek Tıkla Sistem Bakımı:** Seçili kategorilerdeki tüm temizlik ve RAM optimizasyonu tek butonla, arka planda çalışır — arayüz asla donmaz.
- **Seçilebilir Temizlik Kategorileri:** Geçici dosyalar, tarayıcı önbellekleri (Chrome, Edge, Brave, Opera/Opera GX, Firefox — tüm profiller), Discord, GPU shader önbellekleri, Windows hata raporları (WER), Windows Update önbelleği, GPU kurulum kalıntıları ve Geri Dönüşüm Kutusu. Her kategori Ayarlar sekmesinden açılıp kapatılabilir.
- **Güvenli RAM Optimizasyonu:** Native Windows API'leri ile süreçlerin kullanmadığı fiziksel bellek geri kazanılır; kritik sistem süreçleri asla dokunulmaz.
- **Akıllı Oto RAM Boşaltma:** RAM belirlediğiniz eşiği aşınca otomatik temizlik — 5 dakikalık bekleme süresi ve histerezis ile sistemi yormadan.
- **Sistem Tepsisi:** Pencereyi kapatınca uygulama tepside yaşamaya devam eder (ayarlardan kapatılabilir); tepsiden tek tıkla bakım yapılabilir.
- **Windows ile Başlatma & Haftalık Otomatik Temizlik:** Ayarlardan tek tikle etkinleştirilir.
- **Disk Analizi:** Kullanıcı profilinizdeki en büyük 10 klasörü gösterir (salt okunur, ilerleme göstergeli).
- **Fotokapan (CPU sıçrama kaydedici):** CPU %85 üstünde kaldığında sorumlu süreçleri, sürücü (kesme/DPC) payını ve Defender taramalarını kaydeder. Fotokapan sekmesi son 7 günün en sık sorumlularını ve son sıçramaları listeler; kurma/güncelleme/kaldırma oradan yapılır.
- **İstatistikler:** Bugüne kadar toplam temizlenen alan ve bakım sayısı kaydedilir.
- **TR / EN Dil Desteği** ve gerçek zamanlı CPU/RAM/uptime monitörü.

### 🇺🇸 English
- **One-Click Maintenance:** All cleanup and RAM optimization runs on a background thread — the UI never freezes.
- **Selectable Cleanup Categories:** Temp files, browser caches (Chrome, Edge, Brave, Opera/Opera GX, Firefox — all profiles), Discord, GPU shader caches, Windows Error Reporting, Windows Update cache, GPU installer leftovers, and the Recycle Bin. Toggle each category in Settings.
- **Safe RAM Optimization:** Uses native Windows APIs to trim idle working sets; critical system processes are never touched.
- **Smart Auto-Boost:** Automatically trims RAM when usage crosses your threshold — with a 5-minute cooldown and hysteresis so it never thrashes your system.
- **System Tray:** Closing the window keeps OpenRelax alive in the tray (optional); run maintenance straight from the tray menu.
- **Run at Startup & Weekly Scheduled Cleanup:** One checkbox each in Settings.
- **Disk Analysis:** Shows the 10 largest folders in your user profile (read-only, with progress).
- **Spike Trap (CPU spike recorder):** Records the culprit processes, driver (interrupt/DPC) share and Defender scans whenever CPU stays above 85%. The Spike Trap tab lists the top culprits of the last 7 days and the recent spikes, and installs/updates/removes the trap.
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

### Fotokapan (CPU spike trap)

[fotokapan.ps1](fotokapan.ps1) runs independently of the GUI as a SYSTEM scheduled task, so it keeps recording while OpenRelax is closed or the machine is pegged. When total CPU stays ≥85% for 4 s it measures the burst itself and logs the top processes (CPU %, parent, command line), recently started processes and unattributed interrupt/DPC time. If Microsoft Defender is a top consumer it notes a running on-demand scan, or otherwise attaches a 30 s Defender performance report (at most every 6 h).

- Install / update / remove: the buttons on the **Fotokapan** tab (asks for administrator rights), or in an admin PowerShell `.\fotokapan.ps1 -Install` / `.\fotokapan.ps1 -Uninstall`
- Output in `C:\ProgramData\OpenRelax\Fotokapan\` (readable only by SYSTEM, Administrators and the installing user):
  - `fotokapan-YYYY-MM.log` — human-readable report (**Open log** button)
  - `spikes-YYYY-MM.jsonl` — one JSON record per line (`monitor`, `start`, `ongoing`, `end`); the tab reads only this
  - `durum.json` — heartbeat, rewritten every minute

---

## Testler / Tests

Stress tests live in [tests/](tests) (Windows PowerShell 5.1, run from the repo root):

| Script | What it checks |
|---|---|
| `tests\engine-stress.ps1` | Scan/clean engine in a worker runspace on a 30 000-file synthetic tree with traps (junction loop, junction to an outside sentinel, held-open file, < 24 h files, read-only/hidden, bracket/Turkish names, deep and > 260-char paths): nothing outside the tree is touched, progress beats keep coming, memory stays bounded. |
| `tests\fotokapan-stress.ps1` | A private Fotokapan instance through a storm of CPU bursts: every burst caught and attributed, JSONL contract valid, monitor overhead and handles/memory stable, the OpenRelax reader survives damaged lines. Pause the installed trap first (`Stop-ScheduledTask 'OpenRelax Fotokapan'`) to keep the synthetic bursts out of its statistics. |
| `tests\gui-stress.ps1` | Drives the real GUI handlers for N cycles (view switches, language re-apply, background scans, Fotokapan list re-render on 300 synthetic spikes) and checks for handler errors and GDI/USER/handle/memory leaks, then starts and closes the app repeatedly. The window is visible while it runs; nothing is cleaned and no setting is saved. |

Test hooks (environment variables): `OPENRELAX_SMOKETEST=1|<seconds>` auto-close, `OPENRELAX_STRESS=<cycles>` with `OPENRELAX_STRESS_REPORT=<file.json>`, `OPENRELAX_TRAP_DIR=<folder>`.

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
