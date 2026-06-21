# Required assemblies for Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 1. Native Windows API helper definitions
if (-not ([System.Management.Automation.PSTypeName]"Win32Helper").Type) {
    $apiSource = @"
    using System;
    using System.Runtime.InteropServices;
    
    public class Win32Helper {
        [DllImport("psapi.dll", SetLastError = true)]
        public static extern bool EmptyWorkingSet(IntPtr hProcess);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        public struct MEMORYSTATUSEX {
            public uint dwLength;
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;
            public void Init() {
                this.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

        [DllImport("kernel32.dll")]
        public static extern ulong GetTickCount64();

        public static MEMORYSTATUSEX GetMemoryStatus() {
            MEMORYSTATUSEX memStatus = new MEMORYSTATUSEX();
            memStatus.Init();
            GlobalMemoryStatusEx(ref memStatus);
            return memStatus;
        }

        public static TimeSpan GetSystemUptime() {
            return TimeSpan.FromMilliseconds(GetTickCount64());
        }
    }
"@
    Add-Type -TypeDefinition $apiSource -ErrorAction SilentlyContinue
}

# 2. Setup the GUI Window (Form)
$form = New-Object System.Windows.Forms.Form
$form.Text = "OpenRelax PC Care"
$form.Size = New-Object System.Drawing.Size(680, 460)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B0F19')
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

# Force DoubleBuffering to prevent UI flickering on updates
$form.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic).SetValue($form, $true, $null)

# Initialize CPU history list for real-time line graph
$script:cpuHistory = [System.Collections.Generic.List[int]]::new()
for ($i = 0; $i -lt 20; $i++) { $script:cpuHistory.Add(0) }
$script:pulse = $false

# Custom helper function to apply rounded regions to controls
function Set-RoundedRegion {
    param($control, $radius)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $arcRect = New-Object System.Drawing.Rectangle(0, 0, $radius, $radius)
    
    # Top Left
    $path.AddArc($arcRect, 180, 90)
    # Top Right
    $arcRect.X = $control.Width - $radius
    $path.AddArc($arcRect, 270, 90)
    # Bottom Right
    $arcRect.Y = $control.Height - $radius
    $path.AddArc($arcRect, 0, 90)
    # Bottom Left
    $arcRect.X = 0
    $path.AddArc($arcRect, 90, 90)
    
    $path.CloseAllFigures()
    $control.Region = New-Object System.Drawing.Region($path)
}

# Draw a beautiful primary blue/purple border around the form on Paint
$form.add_Paint({
    param($sender, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#3B82F6'), 1.5)
    $e.Graphics.DrawRectangle($pen, 0, 0, $form.Width - 1, $form.Height - 1)
})

# 3. Create custom Title Bar
$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Size = New-Object System.Drawing.Size(680, 42)
$titleBar.Location = New-Object System.Drawing.Point(0, 0)
$titleBar.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
$form.Controls.Add($titleBar)

# Custom title bar divider line
$titleBar.add_Paint({
    param($sender, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#1E293B'), 1)
    $e.Graphics.DrawLine($pen, 0, $titleBar.Height - 1, $titleBar.Width, $titleBar.Height - 1)
})

# Title Bar Dragging Logic
$script:drag = $false
$script:mousePos = $null

$titleBar.add_MouseDown({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:drag = $true
        $script:mousePos = [System.Windows.Forms.Cursor]::Position
    }
})
$titleBar.add_MouseMove({
    param($sender, $e)
    if ($script:drag) {
        $diffX = [System.Windows.Forms.Cursor]::Position.X - $script:mousePos.X
        $diffY = [System.Windows.Forms.Cursor]::Position.Y - $script:mousePos.Y
        $form.Left = $form.Left + $diffX
        $form.Top = $form.Top + $diffY
        $script:mousePos = [System.Windows.Forms.Cursor]::Position
    }
})
$titleBar.add_MouseUp({
    $script:drag = $false
})

# Green Logo Indicator in TitleBar
$logoDot = New-Object System.Windows.Forms.Panel
$logoDot.Size = New-Object System.Drawing.Size(8, 8)
$logoDot.Location = New-Object System.Drawing.Point(15, 17)
$logoDot.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#10B981')
$titleBar.Controls.Add($logoDot)
Set-RoundedRegion $logoDot 8

# Title Text
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "OpenRelax PC Care v1.0"
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$titleLabel.Location = New-Object System.Drawing.Point(30, 11)
$titleLabel.AutoSize = $true
$titleBar.Controls.Add($titleLabel)

# Title Close Button (X)
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Size = New-Object System.Drawing.Size(42, 42)
$btnClose.Location = New-Object System.Drawing.Point(638, 0)
$btnClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.Text = "X"
$btnClose.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnClose.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$btnClose.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnClose.add_MouseEnter({ $btnClose.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#EF4444'); $btnClose.ForeColor = [System.Drawing.Color]::White })
$btnClose.add_MouseLeave({ $btnClose.BackColor = [System.Drawing.Color]::Transparent; $btnClose.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8') })
$btnClose.add_Click({ $form.Close() })
$titleBar.Controls.Add($btnClose)

# Title Minimize Button (-)
$btnMin = New-Object System.Windows.Forms.Button
$btnMin.Size = New-Object System.Drawing.Size(42, 42)
$btnMin.Location = New-Object System.Drawing.Point(596, 0)
$btnMin.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnMin.FlatAppearance.BorderSize = 0
$btnMin.Text = "-"
$btnMin.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnMin.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$btnMin.Cursor = [System.Windows.Forms.Cursors]::Hand
$btnMin.add_MouseEnter({ $btnMin.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#334155'); $btnMin.ForeColor = [System.Drawing.Color]::White })
$btnMin.add_MouseLeave({ $btnMin.BackColor = [System.Drawing.Color]::Transparent; $btnMin.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8') })
$btnMin.add_Click({ $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized })
$titleBar.Controls.Add($btnMin)

# 4. Helper to create rounded card panels
$global:cardHoverStates = @{}

function Create-Card {
    param($parent, $location, $size)
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = $location
    $card.Size = $size
    $card.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#161F30')
    $parent.Controls.Add($card)
    
    # Set rounded shape
    Set-RoundedRegion $card 16
    
    # Draw nice border border lines on Paint
    $card.add_Paint({
        param($sender, $e)
        $cardName = $sender.GetHashCode().ToString()
        $isHovered = $global:cardHoverStates[$cardName] -eq $true
        $borderColor = if ($isHovered) { '#3B82F6' } else { '#1E293B' }
        $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($borderColor), 1.5)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $radius = 16
        $arcRect = New-Object System.Drawing.Rectangle(0, 0, $radius, $radius)
        $path.AddArc($arcRect, 180, 90)
        $arcRect.X = $sender.Width - $radius - 1
        $path.AddArc($arcRect, 270, 90)
        $arcRect.Y = $sender.Height - $radius - 1
        $path.AddArc($arcRect, 0, 90)
        $arcRect.X = 0
        $path.AddArc($arcRect, 90, 90)
        $path.CloseAllFigures()
        
        $e.Graphics.DrawPath($pen, $path)
        $pen.Dispose()
        $path.Dispose()
    })
    return $card
}

function Register-CardHover {
    param($card)
    $cardName = $card.GetHashCode().ToString()
    $global:cardHoverStates[$cardName] = $false
    
    $hoverEnter = {
        $global:cardHoverStates[$cardName] = $true
        $card.Invalidate()
    }.GetNewClosure()
    
    $hoverLeave = {
        $clientPos = $card.PointToClient([System.Windows.Forms.Cursor]::Position)
        if (-not $card.ClientRectangle.Contains($clientPos)) {
            $global:cardHoverStates[$cardName] = $false
            $card.Invalidate()
        }
    }.GetNewClosure()
    
    $card.add_MouseEnter($hoverEnter)
    $card.add_MouseLeave($hoverLeave)
    foreach ($ctrl in $card.Controls) {
        $ctrl.add_MouseEnter($hoverEnter)
        $ctrl.add_MouseLeave($hoverLeave)
    }
}

# Left Container Panel
$leftContainer = New-Object System.Windows.Forms.Panel
$leftContainer.Size = New-Object System.Drawing.Size(260, 390)
$leftContainer.Location = New-Object System.Drawing.Point(18, 56)
$form.Controls.Add($leftContainer)

# -- CARD 1: RAM (Donut Chart) --
$ramCard = Create-Card $leftContainer (New-Object System.Drawing.Point(0, 0)) (New-Object System.Drawing.Size(260, 105))

$ramTitle = New-Object System.Windows.Forms.Label
$ramTitle.Text = "BELLEK (RAM) DURUMU"
$ramTitle.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$ramTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$ramTitle.Location = New-Object System.Drawing.Point(12, 10)
$ramTitle.AutoSize = $true
$ramCard.Controls.Add($ramTitle)

$ramDescLabel = New-Object System.Windows.Forms.Label
$ramDescLabel.Text = "Sistem bellek dolulugu ve kullanim detaylari."
$ramDescLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Regular)
$ramDescLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$ramDescLabel.Location = New-Object System.Drawing.Point(12, 30)
$ramDescLabel.Size = New-Object System.Drawing.Size(145, 30)
$ramCard.Controls.Add($ramDescLabel)

$ramDetailsLabel = New-Object System.Windows.Forms.Label
$ramDetailsLabel.Text = "0.0 GB / 0.0 GB"
$ramDetailsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$ramDetailsLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')
$ramDetailsLabel.Location = New-Object System.Drawing.Point(12, 65)
$ramDetailsLabel.Size = New-Object System.Drawing.Size(145, 20)
$ramCard.Controls.Add($ramDetailsLabel)

# Donut Chart centered label placed over the circle
$ramPercentLabel = New-Object System.Windows.Forms.Label
$ramPercentLabel.Text = "0%"
$ramPercentLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11.5, [System.Drawing.FontStyle]::Bold)
$ramPercentLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$ramPercentLabel.BackColor = [System.Drawing.Color]::Transparent
$ramPercentLabel.Location = New-Object System.Drawing.Point(165, 15)
$ramPercentLabel.Size = New-Object System.Drawing.Size(75, 75)
$ramPercentLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$ramCard.Controls.Add($ramPercentLabel)

# Donut Chart Custom Draw on Card Paint
$ramCard.add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    # Circle bounds
    $rect = New-Object System.Drawing.Rectangle(165, 15, 75, 75)
    
    # Draw dark background track
    $trackPen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#0B0F19'), 7)
    $g.DrawEllipse($trackPen, $rect)
    
    # Draw arc
    $sweepAngle = [float](360 * ([float]($ramPercentLabel.Text.Replace('%', '')) / 100))
    if ($sweepAngle -gt 360) { $sweepAngle = 360 }
    if ($sweepAngle -gt 0) {
        $color1 = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6') # Blue
        $color2 = [System.Drawing.ColorTranslator]::FromHtml('#EC4899') # Pink
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $color1, $color2, 45.0)
        $valuePen = New-Object System.Drawing.Pen($brush, 7)
        $valuePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $valuePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $g.DrawArc($valuePen, $rect, -90, $sweepAngle)
        $valuePen.Dispose()
        $brush.Dispose()
    }
    
    $trackPen.Dispose()
})
Register-CardHover $ramCard

# -- CARD 2: CPU (Real-Time Line Graph) --
$cpuCard = Create-Card $leftContainer (New-Object System.Drawing.Point(0, 120)) (New-Object System.Drawing.Size(260, 105))

$cpuTitle = New-Object System.Windows.Forms.Label
$cpuTitle.Text = "ISLEMCI (CPU) DALGASI"
$cpuTitle.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$cpuTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$cpuTitle.Location = New-Object System.Drawing.Point(12, 10)
$cpuTitle.AutoSize = $true
$cpuCard.Controls.Add($cpuTitle)

$cpuPercentLabel = New-Object System.Windows.Forms.Label
$cpuPercentLabel.Text = "0%"
$cpuPercentLabel.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$cpuPercentLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#8B5CF6')
$cpuPercentLabel.Location = New-Object System.Drawing.Point(10, 32)
$cpuPercentLabel.AutoSize = $true
$cpuCard.Controls.Add($cpuPercentLabel)

$cpuDetailsLabel = New-Object System.Windows.Forms.Label
$cpuDetailsLabel.Text = "Islemci Anlik Yuk"
$cpuDetailsLabel.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Regular)
$cpuDetailsLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$cpuDetailsLabel.Location = New-Object System.Drawing.Point(12, 65)
$cpuDetailsLabel.Size = New-Object System.Drawing.Size(85, 30)
$cpuCard.Controls.Add($cpuDetailsLabel)

# Line Graph Drawing on Card Paint
$cpuCard.add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    # Graph Area: X=110, Y=30, Width=135, Height=55
    $gridPen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#0B0F19'), 1)
    
    # Horizontal grid lines
    $g.DrawLine($gridPen, 110, 48, 245, 48)
    $g.DrawLine($gridPen, 110, 66, 245, 66)
    
    # Draw graph filled area and line
    if ($script:cpuHistory.Count -gt 1) {
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $stepX = 135 / 19
        
        $points = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        for ($i = 0; $i -lt $script:cpuHistory.Count; $i++) {
            $px = 110 + ($i * $stepX)
            $py = 85 - ($script:cpuHistory[$i] / 100 * 50)
            $points.Add((New-Object System.Drawing.PointF($px, $py)))
        }
        
        $firstX = 110
        $lastX = 110 + (($script:cpuHistory.Count - 1) * $stepX)
        $points.Add((New-Object System.Drawing.PointF($lastX, 85)))
        $points.Add((New-Object System.Drawing.PointF($firstX, 85)))
        
        $path.AddLines($points.ToArray())
        $path.CloseAllFigures()
        
        $gradRect = New-Object System.Drawing.Rectangle(110, 35, 135, 50)
        $colorTop = [System.Drawing.Color]::FromArgb(80, 139, 92, 246)
        $colorBottom = [System.Drawing.Color]::FromArgb(0, 139, 92, 246)
        $fillBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($gradRect, $colorTop, $colorBottom, 90.0)
        $g.FillPath($fillBrush, $path)
        
        $graphPen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#8B5CF6'), 2)
        for ($i = 0; $i -lt ($script:cpuHistory.Count - 1); $i++) {
            $x1 = 110 + ($i * $stepX)
            $y1 = 85 - ($script:cpuHistory[$i] / 100 * 50)
            $x2 = 110 + (($i + 1) * $stepX)
            $y2 = 85 - ($script:cpuHistory[$i+1] / 100 * 50)
            $g.DrawLine($graphPen, $x1, $y1, $x2, $y2)
        }
        
        $graphPen.Dispose()
        $fillBrush.Dispose()
        $path.Dispose()
    }
    $gridPen.Dispose()
})
Register-CardHover $cpuCard

# -- CARD 3: SYSTEM INFO --
$sysCard = Create-Card $leftContainer (New-Object System.Drawing.Point(0, 240)) (New-Object System.Drawing.Size(260, 135))

$sysTitle = New-Object System.Windows.Forms.Label
$sysTitle.Text = "SISTEM DETAYLARI"
$sysTitle.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$sysTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$sysTitle.Location = New-Object System.Drawing.Point(12, 10)
$sysTitle.AutoSize = $true
$sysCard.Controls.Add($sysTitle)

# Uptime Row
$lblUptimeName = New-Object System.Windows.Forms.Label
$lblUptimeName.Text = "Calisma Suresi:"
$lblUptimeName.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblUptimeName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblUptimeName.Location = New-Object System.Drawing.Point(12, 35)
$lblUptimeName.AutoSize = $true
$sysCard.Controls.Add($lblUptimeName)

$lblUptimeVal = New-Object System.Windows.Forms.Label
$lblUptimeVal.Text = "-"
$lblUptimeVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblUptimeVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblUptimeVal.Location = New-Object System.Drawing.Point(120, 35)
$lblUptimeVal.Size = New-Object System.Drawing.Size(128, 20)
$lblUptimeVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$sysCard.Controls.Add($lblUptimeVal)

# Process Count Row
$lblProcName = New-Object System.Windows.Forms.Label
$lblProcName.Text = "Islem Sayisi:"
$lblProcName.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblProcName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblProcName.Location = New-Object System.Drawing.Point(12, 65)
$lblProcName.AutoSize = $true
$sysCard.Controls.Add($lblProcName)

$lblProcVal = New-Object System.Windows.Forms.Label
$lblProcVal.Text = "-"
$lblProcVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblProcVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblProcVal.Location = New-Object System.Drawing.Point(120, 65)
$lblProcVal.Size = New-Object System.Drawing.Size(128, 20)
$lblProcVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$sysCard.Controls.Add($lblProcVal)

# Cleanable Junk Size Row
$lblJunkName = New-Object System.Windows.Forms.Label
$lblJunkName.Text = "Gecici Dosya:"
$lblJunkName.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblJunkName.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblJunkName.Location = New-Object System.Drawing.Point(12, 95)
$lblJunkName.AutoSize = $true
$sysCard.Controls.Add($lblJunkName)

$lblJunkVal = New-Object System.Windows.Forms.Label
$lblJunkVal.Text = "Taranıyor..."
$lblJunkVal.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$lblJunkVal.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$lblJunkVal.Location = New-Object System.Drawing.Point(120, 95)
$lblJunkVal.Size = New-Object System.Drawing.Size(128, 20)
$lblJunkVal.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$sysCard.Controls.Add($lblJunkVal)

Register-CardHover $sysCard


# Right Side Container Panel
$rightContainer = New-Object System.Windows.Forms.Panel
$rightContainer.Size = New-Object System.Drawing.Size(368, 390)
$rightContainer.Location = New-Object System.Drawing.Point(294, 56)
$form.Controls.Add($rightContainer)

# Header Title
$headerTitle = New-Object System.Windows.Forms.Label
$headerTitle.Text = "Sistem Bakimi ve Temizlik"
$headerTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$headerTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$headerTitle.Location = New-Object System.Drawing.Point(0, 0)
$headerTitle.AutoSize = $true
$rightContainer.Controls.Add($headerTitle)

# Header Subtitle Description
$headerSub = New-Object System.Windows.Forms.Label
$headerSub.Text = "Tek butonla tüm gereksiz çerezleri, tarayıcı önbelleklerini ve disk çöplerini temizleyin, RAM bellek alanlarını boşaltın."
$headerSub.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$headerSub.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$headerSub.Location = New-Object System.Drawing.Point(0, 26)
$headerSub.Size = New-Object System.Drawing.Size(368, 36)
$rightContainer.Controls.Add($headerSub)

# Action button: One-Click System Maintenance (Custom Gradient Paint)
$btnOneClick = New-Object System.Windows.Forms.Button
$btnOneClick.Size = New-Object System.Drawing.Size(368, 46)
$btnOneClick.Location = New-Object System.Drawing.Point(0, 68)
$btnOneClick.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnOneClick.FlatAppearance.BorderSize = 0
$btnOneClick.Text = "Tek Tikla Sistem Bakimi Yap"
$btnOneClick.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
$btnOneClick.Cursor = [System.Windows.Forms.Cursors]::Hand
$rightContainer.Controls.Add($btnOneClick)
Set-RoundedRegion $btnOneClick 8

$btnOneClick.add_MouseEnter({ $btnOneClick.Invalidate() })
$btnOneClick.add_MouseLeave({ $btnOneClick.Invalidate() })
$btnOneClick.add_MouseDown({ $btnOneClick.Invalidate() })
$btnOneClick.add_MouseUp({ $btnOneClick.Invalidate() })

$btnOneClick.add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    # Gradient Colors
    $color1 = [System.Drawing.ColorTranslator]::FromHtml('#7C3AED')
    $color2 = [System.Drawing.ColorTranslator]::FromHtml('#EC4899')
    
    if (-not $btnOneClick.Enabled) {
        $color1 = [System.Drawing.ColorTranslator]::FromHtml('#3B1D5A')
        $color2 = [System.Drawing.ColorTranslator]::FromHtml('#5B1D45')
    } elseif ($btnOneClick.Capture -and $btnOneClick.ClientRectangle.Contains($btnOneClick.PointToClient([System.Windows.Forms.Cursor]::Position))) {
        # Active
        $color1 = [System.Drawing.ColorTranslator]::FromHtml('#6D28D9')
        $color2 = [System.Drawing.ColorTranslator]::FromHtml('#DB2777')
    } elseif ($btnOneClick.ClientRectangle.Contains($btnOneClick.PointToClient([System.Windows.Forms.Cursor]::Position))) {
        # Hover
        $color1 = [System.Drawing.ColorTranslator]::FromHtml('#8B5CF6')
        $color2 = [System.Drawing.ColorTranslator]::FromHtml('#F472B6')
    }
    
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($btnOneClick.ClientRectangle, $color1, $color2, 0.0)
    
    # Path
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $radius = 8
    $arcRect = New-Object System.Drawing.Rectangle(0, 0, $radius, $radius)
    $path.AddArc($arcRect, 180, 90)
    $arcRect.X = $btnOneClick.Width - $radius - 1
    $path.AddArc($arcRect, 270, 90)
    $arcRect.Y = $btnOneClick.Height - $radius - 1
    $path.AddArc($arcRect, 0, 90)
    $arcRect.X = 0
    $path.AddArc($arcRect, 90, 90)
    $path.CloseAllFigures()
    
    $g.FillPath($brush, $path)
    
    $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString($btnOneClick.Text, $btnOneClick.Font, $textBrush, (New-Object System.Drawing.RectangleF(0, 0, $btnOneClick.Width, $btnOneClick.Height)), $sf)
    
    $brush.Dispose()
    $path.Dispose()
    $textBrush.Dispose()
    $sf.Dispose()
})

# Console terminal logging panel
$logPanel = New-Object System.Windows.Forms.Panel
$logPanel.Size = New-Object System.Drawing.Size(368, 215)
$logPanel.Location = New-Object System.Drawing.Point(0, 125)
$logPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#070A13')
$rightContainer.Controls.Add($logPanel)
Set-RoundedRegion $logPanel 10

# Outline border for logging panel
$logPanel.add_Paint({
    param($sender, $e)
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml('#1E293B'), 1)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $radius = 10
    $arcRect = New-Object System.Drawing.Rectangle(0, 0, $radius, $radius)
    $path.AddArc($arcRect, 180, 90)
    $arcRect.X = $logPanel.Width - $radius - 1
    $path.AddArc($arcRect, 270, 90)
    $arcRect.Y = $logPanel.Height - $radius - 1
    $path.AddArc($arcRect, 0, 90)
    $arcRect.X = 0
    $path.AddArc($arcRect, 90, 90)
    $path.CloseAllFigures()
    $e.Graphics.DrawPath($pen, $path)
})

# Log text box itself inside the rounded panel
$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Location = New-Object System.Drawing.Point(8, 8)
$logBox.Size = New-Object System.Drawing.Size(352, 199)
$logBox.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#070A13')
$logBox.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#10B981')
$logBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$logBox.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$logBox.ReadOnly = $true
$logPanel.Controls.Add($logBox)

# Footer Status Label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Durum: Hazir"
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblStatus.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$lblStatus.Location = New-Object System.Drawing.Point(0, 352)
$lblStatus.Size = New-Object System.Drawing.Size(200, 20)
$rightContainer.Controls.Add($lblStatus)

# Auto Boost Switch & Labels
$script:autoBoostEnabled = $false

$lblAuto = New-Object System.Windows.Forms.Label
$lblAuto.Text = "Oto RAM Bosalt:"
$lblAuto.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblAuto.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblAuto.Location = New-Object System.Drawing.Point(90, 350)
$lblAuto.Size = New-Object System.Drawing.Size(100, 20)
$lblAuto.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$rightContainer.Controls.Add($lblAuto)

$switchPanel = New-Object System.Windows.Forms.Panel
$switchPanel.Size = New-Object System.Drawing.Size(36, 20)
$switchPanel.Location = New-Object System.Drawing.Point(196, 350)
$switchPanel.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#334155')
$switchPanel.Cursor = [System.Windows.Forms.Cursors]::Hand
$rightContainer.Controls.Add($switchPanel)
Set-RoundedRegion $switchPanel 10

$switchPanel.add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    $bgBrush = if ($script:autoBoostEnabled) {
        New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#10B981'))
    } else {
        New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml('#334155'))
    }
    
    $g.FillRectangle($bgBrush, 0, 0, $switchPanel.Width, $switchPanel.Height)
    $bgBrush.Dispose()
    
    $knobBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $knobX = if ($script:autoBoostEnabled) { 18 } else { 2 }
    $g.FillEllipse($knobBrush, $knobX, 2, 16, 16)
    $knobBrush.Dispose()
})

$switchPanel.add_Click({
    $script:autoBoostEnabled = -not $script:autoBoostEnabled
    $switchPanel.Invalidate()
})

# Auto Boost Limit Label
$lblLimit = New-Object System.Windows.Forms.Label
$lblLimit.Text = "Sinir:"
$lblLimit.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblLimit.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#94A3B8')
$lblLimit.Location = New-Object System.Drawing.Point(245, 350)
$lblLimit.Size = New-Object System.Drawing.Size(55, 20)
$lblLimit.TextAlign = [System.Drawing.ContentAlignment]::TopRight
$rightContainer.Controls.Add($lblLimit)

# Auto Boost Limit Dropdown
$cmbLimit = New-Object System.Windows.Forms.ComboBox
$cmbLimit.Location = New-Object System.Drawing.Point(308, 348)
$cmbLimit.Size = New-Object System.Drawing.Size(60, 22)
$cmbLimit.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#161F30')
$cmbLimit.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$cmbLimit.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbLimit.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
[void]$cmbLimit.Items.Add("%70")
[void]$cmbLimit.Items.Add("%75")
[void]$cmbLimit.Items.Add("%80")
[void]$cmbLimit.Items.Add("%85")
[void]$cmbLimit.Items.Add("%90")
$cmbLimit.SelectedIndex = 3
$rightContainer.Controls.Add($cmbLimit)


# 5. Core logic functions
function Write-Log {
    param(
        [string]$Message,
        [string]$Type = "info"
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    $logAction = [Action]{
        # Append Timestamp in gray color
        $logBox.SelectionStart = $logBox.Text.Length
        $logBox.SelectionLength = 0
        $logBox.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml('#475569')
        $logBox.AppendText("[$timestamp] ")
        
        # Append Prefix in specific status color
        $prefix = ""
        $prefixColor = '#3B82F6'
        switch ($Type) {
            "success" {
                $prefix = "[OK] "
                $prefixColor = '#10B981'
            }
            "warn" {
                $prefix = "[!] "
                $prefixColor = '#F59E0B'
            }
            "error" {
                $prefix = "[X] "
                $prefixColor = '#EF4444'
            }
            default {
                $prefix = "[i] "
                $prefixColor = '#06B6D4'
            }
        }
        $logBox.SelectionStart = $logBox.Text.Length
        $logBox.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml($prefixColor)
        $logBox.AppendText($prefix)
        
        # Append actual message in slate color
        $logBox.SelectionStart = $logBox.Text.Length
        $logBox.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml('#E2E8F0')
        $logBox.AppendText("$Message`n")
        
        # Scroll to bottom
        $logBox.SelectionStart = $logBox.Text.Length
        $logBox.ScrollToCaret()
    }
    
    if ($form.IsHandleCreated) {
        $form.Invoke($logAction)
    } else {
        & $logAction
    }
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) {
        return "$([Math]::Round($Bytes / 1GB, 2)) GB"
    } elseif ($Bytes -ge 1MB) {
        return "$([Math]::Round($Bytes / 1MB, 1)) MB"
    } elseif ($Bytes -ge 1KB) {
        return "$([Math]::Round($Bytes / 1KB, 0)) KB"
    } else {
        return "$Bytes B"
    }
}

function Get-JunkPaths {
    $paths = @()
    if (Test-Path $env:TEMP) {
        $paths += $env:TEMP
    }
    $sysTemp = "$env:windir\Temp"
    if (Test-Path $sysTemp) {
        $paths += $sysTemp
    }
    $chromeCache = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    if (Test-Path $chromeCache) {
        $paths += $chromeCache
    }
    $edgeCache = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    if (Test-Path $edgeCache) {
        $paths += $edgeCache
    }
    $braveCache = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache"
    if (Test-Path $braveCache) {
        $paths += $braveCache
    }
    $operaCache = "$env:LOCALAPPDATA\Opera Software\Opera Stable\Cache"
    if (Test-Path $operaCache) {
        $paths += $operaCache
    }
    $discordCache = "$env:APPDATA\discord\Cache"
    if (Test-Path $discordCache) {
        $paths += $discordCache
    }
    $discordCodeCache = "$env:APPDATA\discord\Code Cache"
    if (Test-Path $discordCodeCache) {
        $paths += $discordCodeCache
    }
    $firefoxRoot = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $firefoxRoot) {
        $profiles = Get-ChildItem -Path $firefoxRoot -Directory -ErrorAction SilentlyContinue
        foreach ($p in $profiles) {
            $pCache = Join-Path $p.FullName "cache2"
            if (Test-Path $pCache) {
                $paths += $pCache
            }
        }
    }
    $d3dCache = "$env:LOCALAPPDATA\D3DSCache"
    if (Test-Path $d3dCache) {
        $paths += $d3dCache
    }
    
    # 1. Windows Error Reporting & Crash Dumps
    $werArchive = "$env:PROGRAMDATA\Microsoft\Windows\WER\ReportArchive"
    if (Test-Path $werArchive) { $paths += $werArchive }
    $werQueue = "$env:PROGRAMDATA\Microsoft\Windows\WER\ReportQueue"
    if (Test-Path $werQueue) { $paths += $werQueue }
    $crashDumps = "$env:LOCALAPPDATA\CrashDumps"
    if (Test-Path $crashDumps) { $paths += $crashDumps }
    
    # 2. Windows Update Download Cache
    $wuDownload = "$env:SystemRoot\SoftwareDistribution\Download"
    if (Test-Path $wuDownload) { $paths += $wuDownload }
    
    # 3. GPU Installer Residues
    if (Test-Path "C:\NVIDIA") { $paths += "C:\NVIDIA" }
    if (Test-Path "C:\AMD") { $paths += "C:\AMD" }
    $nvNetService = "$env:PROGRAMDATA\NVIDIA Corporation\NetService"
    if (Test-Path $nvNetService) { $paths += $nvNetService }
    
    # 4. Setup & Upgrade Logs
    $panther = "$env:SystemRoot\Panther"
    if (Test-Path $panther) { $paths += $panther }
    $sysLogs = "$env:SystemRoot\Logs"
    if (Test-Path $sysLogs) { $paths += $sysLogs }
    
    # 5. Prefetch Data
    $prefetch = "$env:SystemRoot\Prefetch"
    if (Test-Path $prefetch) { $paths += $prefetch }
    
    # 6. Additional GPU Shader Caches
    $nvCache = "$env:LOCALAPPDATA\NVIDIA\DXCache"
    if (Test-Path $nvCache) { $paths += $nvCache }
    $amdCache = "$env:LOCALAPPDATA\AMD\DxCache"
    if (Test-Path $amdCache) { $paths += $amdCache }

    return $paths
}

function Scan-Junk {
    $setAction = [Action]{
        $lblJunkVal.Text = "Hesaplanıyor..."
    }
    if ($form.IsHandleCreated) { $form.Invoke($setAction) } else { & $setAction }
    
    $totalSize = 0
    $fileCount = 0
    $paths = Get-JunkPaths
    
    foreach ($path in $paths) {
        try {
            $files = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue
            foreach ($file in $files) {
                $totalSize += $file.Length
                $fileCount++
            }
        } catch {}
    }
    
    try {
        $sh = New-Object -ComObject Shell.Application
        $bin = $sh.NameSpace(0x0a)
        if ($bin) {
            foreach ($item in $bin.Items()) {
                $totalSize += $item.Size
                $fileCount++
            }
        }
    } catch {}
    
    $updateAction = [Action]{
        if ($totalSize -gt 0) {
            $formatted = Format-Bytes $totalSize
            $lblJunkVal.Text = $formatted
            Write-Log "Gereksiz dosya taramasi bitti: $fileCount dosya ($formatted) bulundu." "info"
        } else {
            $lblJunkVal.Text = "Temiz"
            Write-Log "Geçici dosyalar temiz durumda." "success"
        }
    }
    if ($form.IsHandleCreated) { $form.Invoke($updateAction) } else { & $updateAction }
}

function Optimize-RAM {
    param([switch]$Silent)
    
    if (-not $Silent) {
        Write-Log "Bellek (RAM) temizleme islemi baslatildi..." "info"
    }
    
    $processes = Get-Process
    $successCount = 0
    $failCount = 0
    
    $memBefore = [Win32Helper]::GetMemoryStatus()
    $beforeAvail = $memBefore.ullAvailPhys
    
    foreach ($proc in $processes) {
        if ($proc.Id -eq $PID) { continue }
        try {
            if ($proc.Handle) {
                $res = [Win32Helper]::EmptyWorkingSet($proc.Handle)
                if ($res) {
                    $successCount++
                } else {
                    $failCount++
                }
            }
        } catch {
            $failCount++
        }
    }
    
    try {
        Clear-DnsClientCache -ErrorAction SilentlyContinue
    } catch {}
    
    $memAfter = [Win32Helper]::GetMemoryStatus()
    $afterAvail = $memAfter.ullAvailPhys
    
    $savedBytes = $afterAvail - $beforeAvail
    if ($savedBytes -gt 0) {
        $savedFormatted = Format-Bytes $savedBytes
        Write-Log "RAM Optimizasyonu tamamlandı: $savedFormatted bellek geri kazanildi." "success"
    } else {
        if (-not $Silent) {
            Write-Log "Bellek zaten en optimum seviyede." "info"
        }
    }
}

function Clean-Junk {
    Write-Log "Gecici dosyalar ve cöp kutusu temizleniyor..." "info"
    $deletedCount = 0
    $deletedBytes = 0
    $paths = Get-JunkPaths
    
    foreach ($path in $paths) {
        $items = Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue
        
        $files = $items | Where-Object { -not $_.PSIsContainer }
        $dirs = $items | Where-Object { $_.PSIsContainer } | Sort-Object FullName -Descending
        
        foreach ($file in $files) {
            try {
                $len = $file.Length
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                $deletedBytes += $len
                $deletedCount++
            } catch {
                # Lock or system file bypass
            }
        }
        
        foreach ($dir in $dirs) {
            try {
                $subFiles = Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue
                if ($subFiles.Count -eq 0) {
                    Remove-Item -Path $dir.FullName -Force -Recurse -ErrorAction SilentlyContinue
                }
            } catch {}
        }
    }
    
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Log "Geri Dönüsüm Kutusu bosaltildi." "success"
    } catch {}
    
    $formatted = Format-Bytes $deletedBytes
    Write-Log "Sistem temizligi tamamlandi: $deletedCount dosya silindi ($formatted)." "success"
    
    Scan-Junk
}

# Bind Maintenance Button Click
$btnOneClick.add_Click({
    $btnOneClick.Enabled = $false
    $btnOneClick.Invalidate()
    Write-Log "Tek Tikla Sistem Bakimi baslatildi..." "info"
    
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        # 1. Optimize RAM (EmptyWorkingSet)
        Optimize-RAM
        
        # 2. Clean browser caches, temp files, and recycle bin
        Clean-Junk
        
        # 3. Clean DNS and optimize network connection
        try {
            Write-Log "Ag ve Internet optimizasyonu yapiliyor..." "info"
            Clear-DnsClientCache -ErrorAction SilentlyContinue
            Write-Log "DNS önbellegi ve ag soketleri temizlendi." "success"
        } catch {}
        
        Write-Log "Tüm bakim islemleri basariyla tamamlandi!" "success"
    } catch {
        Write-Log "Bakim sirasinda hata: $_" "error"
    } finally {
        $btnOneClick.Enabled = $true
        $btnOneClick.Invalidate()
    }
})


# 6. Setup the Monitoring Timer
$cpuCounter = New-Object System.Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total")
[void]$cpuCounter.NextValue() # Initialize counter

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.add_Tick({
    try {
        # Update RAM UI
        $memStatus = [Win32Helper]::GetMemoryStatus()
        $totalGB = [Math]::Round($memStatus.ullTotalPhys / 1GB, 1)
        $freeGB = [Math]::Round($memStatus.ullAvailPhys / 1GB, 1)
        $usedGB = [Math]::Round(($memStatus.ullTotalPhys - $memStatus.ullAvailPhys) / 1GB, 1)
        $ramLoad = $memStatus.dwMemoryLoad

        $ramPercentLabel.Text = "$ramLoad%"
        $ramDetailsLabel.Text = "$usedGB GB / $totalGB GB"
        $ramCard.Invalidate() # Force Donut repaint

        # Update CPU UI
        $cpuVal = [Math]::Round($cpuCounter.NextValue())
        if ($cpuVal -gt 100) { $cpuVal = 100 }
        $cpuPercentLabel.Text = "$cpuVal%"
        
        # Shift and append to history
        $script:cpuHistory.Add($cpuVal)
        if ($script:cpuHistory.Count -gt 20) { $script:cpuHistory.RemoveAt(0) }
        $cpuCard.Invalidate() # Force line graph repaint

        # Update System Details
        $uptime = [Win32Helper]::GetSystemUptime()
        $lblUptimeVal.Text = [string]::Format("{0}g {1}s {2}d", $uptime.Days, $uptime.Hours, $uptime.Minutes)
        $lblProcVal.Text = (Get-Process).Count.ToString()

        # Pulse logo indicator
        if ($script:pulse) {
            $logoDot.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#059669')
        } else {
            $logoDot.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#10B981')
        }
        $script:pulse = -not $script:pulse

        # Check Auto-Boost
        $limitText = $cmbLimit.SelectedItem.ToString()
        $limitVal = [int]($limitText -replace '%', '')
        if ($script:autoBoostEnabled -and $ramLoad -ge $limitVal) {
            Write-Log "Kritik RAM seviyesi (%$limitVal+)! Otomatik temizlik yapılıyor..." "warn"
            Optimize-RAM -Silent
        }
    } catch {}
})

# Form Load Event
$form.add_Load({
    Write-Log "Sistem taraması başlatıldı..." "info"
    
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Log "Yonetici yetkileri aktif (Tam Sistem Temizligi)." "success"
        $lblStatus.Text = "Durum: Yonetici Modu"
    } else {
        Write-Log "Normal yetkiler ile calisiyor (Sistem dosyalari atlanabilir)." "warn"
        $lblStatus.Text = "Durum: Kullanici Modu"
    }

    $timer.Start()

    # Trigger junk size calculation shortly after rendering window
    $scanTimer = New-Object System.Windows.Forms.Timer
    $scanTimer.Interval = 500
    $scanTimer.add_Tick({
        param($sender, $e)
        $sender.Stop()
        Scan-Junk
        $sender.Dispose()
    })
    $scanTimer.Start()
})

# Run the form message loop
[System.Windows.Forms.Application]::Run($form)

