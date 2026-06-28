Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

$OutputDir = Join-Path (Get-Location) "Day2_Cover"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Brush($hex) {
    return New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
}

function TextBlock($text, $size, $weight = "Normal", $color = "#FFFFFF", $width = 900, $lineHeight = 0) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily("Microsoft YaHei UI, Microsoft YaHei, Segoe UI Emoji")
    $tb.FontSize = $size
    $tb.FontWeight = [System.Windows.FontWeights]::$weight
    $tb.Foreground = Brush $color
    $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $tb.Width = $width
    if ($lineHeight -gt 0) { $tb.LineHeight = $lineHeight }
    return $tb
}

function AddAt($canvas, $element, $x, $y) {
    [System.Windows.Controls.Canvas]::SetLeft($element, [double]$x)
    [System.Windows.Controls.Canvas]::SetTop($element, [double]$y)
    $canvas.Children.Add($element) | Out-Null
}

function RoundedBox($w, $h, $bg, $radius = 20) {
    $border = New-Object System.Windows.Controls.Border
    $border.Width = $w
    $border.Height = $h
    $border.Background = Brush $bg
    $border.CornerRadius = New-Object System.Windows.CornerRadius($radius)
    return $border
}

function AddTextBox($canvas, $text, $x, $y, $w, $h, $bg, $fg, $size, $weight = "Bold", $radius = 18) {
    $border = RoundedBox $w $h $bg $radius
    $border.Padding = New-Object System.Windows.Thickness(22, 4, 22, 4)
    $tb = TextBlock $text $size $weight $fg ($w - 44)
    $tb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $tb.TextAlignment = [System.Windows.TextAlignment]::Center
    $border.Child = $tb
    AddAt $canvas $border $x $y
}

function AddLine($canvas, $x1, $y1, $x2, $y2, $color, $thickness) {
    $line = New-Object System.Windows.Shapes.Line
    $line.X1 = $x1; $line.Y1 = $y1; $line.X2 = $x2; $line.Y2 = $y2
    $line.Stroke = Brush $color
    $line.StrokeThickness = $thickness
    $line.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
    $line.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
    $canvas.Children.Add($line) | Out-Null
}

function SaveCanvas($canvas, $path) {
    $size = New-Object System.Windows.Size(1080,1440)
    $canvas.Measure($size)
    $canvas.Arrange((New-Object System.Windows.Rect($size)))
    $canvas.UpdateLayout()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(1080,1440,96,96,[System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($canvas)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Create)
    $encoder.Save($fs)
    $fs.Close()
}

$canvas = New-Object System.Windows.Controls.Canvas
$canvas.Width = 1080
$canvas.Height = 1440
$canvas.Background = Brush "#6A63F6"

# Decorative quote marks
$leftQuote = [string][char]0x201C
$rightQuote = [string][char]0x201D
$quote = TextBlock $leftQuote 360 "Black" "#C8FF00" 420
$quote.Opacity = 0.95
AddAt $canvas $quote 625 80
$quote2 = TextBlock $rightQuote 360 "Black" "#C8FF00" 420
$quote2.Opacity = 0.95
AddAt $canvas $quote2 785 80

# Top label
AddTextBox $canvas "文科生学AI Day2" 84 116 360 72 "#C8FF00" "#141414" 38 "Black" 4
AddLine $canvas 84 195 435 195 "#FF8B2B" 12

# Main title
AddAt $canvas (TextBlock "我不写代码" 130 "Black" "#FFFFFF" 960 148) 84 410
AddAt $canvas (TextBlock "也要学" 130 "Black" "#FFFFFF" 960 148) 84 575
AddAt $canvas (TextBlock "AI Agent 吗？" 130 "Black" "#FFFFFF" 980 148) 84 740

# Highlight strip
AddTextBox $canvas "Codex 不是聊天框" 92 930 520 82 "#C8FF00" "#141414" 40 "Black" 4
AddLine $canvas 96 1012 602 1012 "#FF8B2B" 12

# Supporting text
AddAt $canvas (TextBlock "普通人也能从一个小问题开始理解它" 32 "Bold" "#FFFFFF" 850 46) 92 1088
AddAt $canvas (TextBlock "ChatGPT 陪我想，Codex 陪我做" 30 "Bold" "#E8E7FF" 850 44) 92 1142

# Small icon
AddAt $canvas (TextBlock "🤖" 78 "Normal" "#FFFFFF" 120) 878 1188

# Footer
AddAt $canvas (TextBlock "SHARE YOUR AI LEARNING HERE ▲" 24 "Bold" "#C8FF00" 600) 330 1364

$out = Join-Path $OutputDir "day2_cover_ai_agent.png"
SaveCanvas $canvas $out
Write-Output $out
