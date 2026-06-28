Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase

$OutputDir = Join-Path (Get-Location) "Day2_Codex_Not_Chatbot_Cards_Emoji"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function Brush($hex) {
    return New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
}

function TextBlock($text, $size, $weight = "Normal", $color = "#222222", $width = 900, $lineHeight = 0) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $text
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily("Microsoft YaHei, Segoe UI Emoji")
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

function RoundedBox($w, $h, $bg, $radius = 24) {
    $border = New-Object System.Windows.Controls.Border
    $border.Width = $w
    $border.Height = $h
    $border.Background = Brush $bg
    $border.CornerRadius = New-Object System.Windows.CornerRadius($radius)
    return $border
}

function AddTextBox($canvas, $text, $x, $y, $w, $h, $bg, $fg = "#222222", $size = 45, $weight = "Bold", $radius = 24) {
    $border = RoundedBox $w $h $bg $radius
    $border.Padding = New-Object System.Windows.Thickness(32, 10, 32, 10)
    $tb = TextBlock $text $size $weight $fg ($w - 64) 0
    $tb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $border.Child = $tb
    AddAt $canvas $border $x $y
}

function AddEmojiRow($canvas, $emoji, $text, $x, $y, $w, $bg = "#EFEAE0", $h = 84, $size = 40) {
    $border = RoundedBox $w $h $bg 24
    $border.Padding = New-Object System.Windows.Thickness(22, 12, 22, 12)
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $sp.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $chip = RoundedBox 62 62 "#FFFFFF" 20
    $em = TextBlock $emoji 34 "Normal" "#222222" 62 0
    $em.TextAlignment = [System.Windows.TextAlignment]::Center
    $em.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $chip.Child = $em
    $sp.Children.Add($chip) | Out-Null

    $txt = TextBlock $text $size "Bold" "#222222" ($w - 120) 48
    $txt.Margin = New-Object System.Windows.Thickness(18, 2, 0, 0)
    $sp.Children.Add($txt) | Out-Null

    $border.Child = $sp
    AddAt $canvas $border $x $y
}

function AddQuestionRow($canvas, $text, $x, $y) {
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $sp.Width = 850
    $sp.Height = 58

    $chip = RoundedBox 52 52 "#EFEAE0" 18
    $em = TextBlock "❓" 28 "Normal" "#222222" 52 0
    $em.TextAlignment = [System.Windows.TextAlignment]::Center
    $em.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $chip.Child = $em
    $sp.Children.Add($chip) | Out-Null

    $txt = TextBlock $text 38 "Bold" "#222222" 760 0
    $txt.Margin = New-Object System.Windows.Thickness(16, 2, 0, 0)
    $sp.Children.Add($txt) | Out-Null
    AddAt $canvas $sp $x $y
}

function AddHeader($canvas, $index, $eyebrow, $accent) {
    AddTextBox $canvas ("{0:D2}" -f $index) 64 58 162 54 $accent "#FFFFFF" 29 "Bold" 28
    AddAt $canvas (TextBlock $eyebrow 31 "Normal" "#65615A" 760) 256 66
}

function AddFooter($canvas, $footer) {
    $line = New-Object System.Windows.Shapes.Line
    $line.X1 = 82; $line.X2 = 998; $line.Y1 = 980; $line.Y2 = 980
    $line.Stroke = Brush "#DED6C8"
    $line.StrokeThickness = 3
    $canvas.Children.Add($line) | Out-Null
    AddAt $canvas (TextBlock $footer 27 "Normal" "#686158" 900) 86 1000
}

function AddImage($canvas, $path, $x, $y, $w, $h) {
    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.UriSource = New-Object System.Uri($path, [System.UriKind]::Absolute)
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.EndInit()
    $img = New-Object System.Windows.Controls.Image
    $img.Source = $bitmap
    $img.Width = $w
    $img.Height = $h
    $img.Stretch = [System.Windows.Media.Stretch]::Uniform
    AddAt $canvas $img $x $y
}

function NewCanvas() {
    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.Width = 1080
    $canvas.Height = 1080
    $canvas.Background = Brush "#F8F6F0"
    return $canvas
}

function SaveCanvas($canvas, $path) {
    $size = New-Object System.Windows.Size(1080,1080)
    $canvas.Measure($size)
    $canvas.Arrange((New-Object System.Windows.Rect($size)))
    $canvas.UpdateLayout()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(1080,1080,96,96,[System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($canvas)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Create)
    $encoder.Save($fs)
    $fs.Close()
}

function SaveCard($index, $canvas) {
    $path = Join-Path $OutputDir ("day2_card_{0:D2}.png" -f $index)
    SaveCanvas $canvas $path
    Write-Output $path
}

$c = NewCanvas
AddHeader $c 1 "文科生学 AI Day2" "#E85D4A"
AddAt $c (TextBlock "Codex 为什么不只是聊天机器人？" 78 "Black" "#222222" 910 88) 92 170
AddAt $c (TextBlock "我不写代码，也开始理解 AI Agent 了" 42 "Normal" "#5F5A52" 900) 92 372
AddAt $c (TextBlock "不是因为它《更高级》。`n而是它让我第一次感觉到：AI 不只是在回答我，也可以和我一起把事情往前推。" 41 "Normal" "#222222" 860 60) 92 485
AddTextBox $c "🤖" 858 820 150 150 "#E85D4A" "#FFFFFF" 66 "Normal" 36
AddFooter $c "Day2｜Codex 不是另一个聊天框"
SaveCard 1 $c

$c = NewCanvas
AddHeader $c 2 "先抛一个问题" "#2F7D75"
AddAt $c (TextBlock "我一开始也很疑惑" 78 "Black" "#222222" 900) 92 175
AddAt $c (TextBlock "我又不是程序员，真的需要学 AI Agent 吗？" 42 "Normal" "#5F5A52" 890) 92 285
AddEmojiRow $c "🫠" "不写代码" 92 420 870
AddEmojiRow $c "💻" "不做计算机工作" 92 525 870
AddEmojiRow $c "🤔" "这个《更高级的 AI》`n和我有什么关系？" 92 630 870 "#EFEAE0" 128 38
AddFooter $c "普通人学 AI，先从真实疑惑开始"
SaveCard 2 $c

$c = NewCanvas
AddHeader $c 3 "我现在的理解" "#D99A2B"
AddAt $c (TextBlock "ChatGPT 和 Codex 的差别" 72 "Black" "#222222" 900 86) 92 175
AddAt $c (TextBlock "一个更像陪我想，一个更像陪我做" 42 "Normal" "#5F5A52" 900) 92 292
$left = RoundedBox 430 390 "#EFEAE0" 30
$left.Padding = New-Object System.Windows.Thickness(34)
$ls = New-Object System.Windows.Controls.StackPanel
$ls.Children.Add((TextBlock "💬 ChatGPT" 42 "Bold" "#222222" 360)) | Out-Null
foreach($t in @("陪你想","解释概念","给建议","帮你把话说明白")) { $tb = TextBlock $t 35 "Bold" "#5F5A52" 340; $tb.Margin = New-Object System.Windows.Thickness(0,18,0,0); $ls.Children.Add($tb) | Out-Null }
$left.Child = $ls
AddAt $c $left 92 410
$right = RoundedBox 430 390 "#EFEAE0" 30
$right.Padding = New-Object System.Windows.Thickness(34)
$rs = New-Object System.Windows.Controls.StackPanel
$rs.Children.Add((TextBlock "🤖 AI Agent / Codex" 40 "Bold" "#222222" 370)) | Out-Null
foreach($t in @("进到任务现场","读文件 / 看路径","拆步骤","执行和验证")) { $tb = TextBlock $t 35 "Bold" "#5F5A52" 340; $tb.Margin = New-Object System.Windows.Thickness(0,18,0,0); $rs.Children.Add($tb) | Out-Null }
$right.Child = $rs
AddAt $c $right 568 410
AddFooter $c "不是谁更高级，而是协作方式不同"
SaveCard 3 $c

$c = NewCanvas
AddHeader $c 4 "一个很小的例子" "#6B6FCF"
AddAt $c (TextBlock "WPS 云文档上传失败" 66 "Black" "#222222" 900) 92 145
AddAt $c (TextBlock "从临时清理，到发现路径问题" 38 "Normal" "#5F5A52" 900) 92 238
$casePath = Join-Path (Get-Location) "assets\day2_wps_case.png"
AddImage $c $casePath 240 300 600 900
AddFooter $c "我学到的不是清理技巧，而是：模糊问题要靠追问变清楚"
SaveCard 4 $c

$c = NewCanvas
AddHeader $c 5 "这件小事让我意识到" "#C6517A"
AddAt $c (TextBlock "AI Agent 不只适合`n《大项目》" 66 "Black" "#222222" 900 78) 92 175
AddAt $c (TextBlock "也适合那些碎、烦、说不清的问题" 40 "Normal" "#5F5A52" 900) 92 365
AddAt $c (TextBlock "它的价值不是《替我一键解决》。" 41 "Normal" "#222222" 900) 92 470
AddTextBox $c "而是陪我把问题拆开" 92 555 916 92 "#C6517A" "#FFFFFF" 46 "Black" 24
AddAt $c (TextBlock "先判断原因，再决定下一步，最后去验证结果。" 41 "Normal" "#222222" 850 60) 92 695
AddFooter $c "AI Agent 的价值，有时就在这些说不清的小麻烦里"
SaveCard 5 $c

$c = NewCanvas
AddHeader $c 6 "我真正想记住的是" "#2E8B57"
AddAt $c (TextBlock "AI 时代重要的能力" 78 "Black" "#222222" 900) 92 175
AddAt $c (TextBlock "可能不是人人都会写代码" 42 "Normal" "#5F5A52" 900) 92 285
AddEmojiRow $c "✨" "发现需求" 92 420 850
AddEmojiRow $c "✨" "说清需求" 92 525 850
AddEmojiRow $c "✨" "判断结果" 92 630 850
AddEmojiRow $c "✨" "决定方向" 92 735 850
AddFooter $c "工具会越来越强，人更要练判断"
SaveCard 6 $c

$c = NewCanvas
AddHeader $c 7 "Day2 的结论" "#1E6EA8"
AddAt $c (TextBlock "文科生不一定要会写代码" 76 "Black" "#222222" 900 88) 92 175
AddAt $c (TextBlock "但要学会和会执行的 AI 协作" 42 "Normal" "#5F5A52" 900) 92 372
AddAt $c (TextBlock "我还在 0 基础阶段，也没完全想明白。`n但我开始觉得：Codex 不只是一个聊天机器人。" 41 "Normal" "#222222" 880 60) 92 482
AddTextBox $c "它更像一种新的协作方式" 92 692 916 92 "#1E6EA8" "#FFFFFF" 46 "Black" 24
AddAt $c (TextBlock "Day3 我想继续记录：`n怎么把竞品分析场景，做成一个 skill。" 39 "Normal" "#222222" 850 55) 92 825
AddFooter $c "下一篇：我把竞品分析做成了一个 skill"
SaveCard 7 $c

