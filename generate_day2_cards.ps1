Add-Type -AssemblyName System.Drawing

$OutputDir = Join-Path (Get-Location) "Day2_Codex_Not_Chatbot_Cards"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

function New-Font($size, $bold = $false) {
    $style = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    return New-Object System.Drawing.Font("Microsoft YaHei", $size, $style, [System.Drawing.GraphicsUnit]::Pixel)
}

function Measure-TextWidth($graphics, $text, $font) {
    return $graphics.MeasureString($text, $font).Width
}

function Wrap-Text($graphics, $text, $font, $maxWidth) {
    if ([string]::IsNullOrWhiteSpace($text)) { return @("") }
    $lines = @()
    foreach ($rawLine in ($text -split "`n")) {
        $line = ""
        foreach ($char in $rawLine.ToCharArray()) {
            $candidate = "$line$char"
            if ((Measure-TextWidth $graphics $candidate $font) -le $maxWidth -or $line.Length -eq 0) {
                $line = $candidate
            } else {
                $lines += $line
                $line = [string]$char
            }
        }
        if ($line.Length -gt 0) { $lines += $line }
    }
    return $lines
}

function Draw-WrappedText($graphics, $text, $font, $brush, $x, $y, $maxWidth, $lineHeight) {
    $lines = Wrap-Text $graphics $text $font $maxWidth
    foreach ($line in $lines) {
        $graphics.DrawString($line, $font, $brush, [float]$x, [float]$y)
        $y += $lineHeight
    }
    return $y
}

function Draw-RoundedRect($graphics, $brush, $x, $y, $w, $h, $r) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($x, $y, $r, $r, 180, 90)
    $path.AddArc($x + $w - $r, $y, $r, $r, 270, 90)
    $path.AddArc($x + $w - $r, $y + $h - $r, $r, $r, 0, 90)
    $path.AddArc($x, $y + $h - $r, $r, $r, 90, 90)
    $path.CloseFigure()
    $graphics.FillPath($brush, $path)
    $path.Dispose()
}

function Save-Card($index, $eyebrow, $title, $subtitle, $blocks, $accentHex, $footer) {
    $W = 1080
    $H = 1080
    $bmp = New-Object System.Drawing.Bitmap($W, $H)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.ColorTranslator]::FromHtml("#F8F6F0"))

    $black = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#222222"))
    $muted = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#65615A"))
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#FFFFFF"))
    $accent = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($accentHex))
    $soft = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#EFEAE0"))
    $linePen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml("#DED6C8"), 3)

    $fontTiny = New-Font 28 $false
    $fontSmall = New-Font 34 $false
    $fontBody = New-Font 43 $false
    $fontBodyBold = New-Font 46 $true
    $fontTitle = New-Font 72 $true
    $fontBig = New-Font 86 $true

    Draw-RoundedRect $g $accent 64 58 162 52 26
    $g.DrawString(("0{0}" -f $index), $fontTiny, $white, 102, 65)
    $g.DrawString($eyebrow, $fontSmall, $muted, 250, 62)

    $y = 155
    $titleFont = if ($title.Length -lt 16) { $fontBig } else { $fontTitle }
    $y = Draw-WrappedText $g $title $titleFont $black 82 $y 900 94
    if ($subtitle) {
        $y += 18
        $y = Draw-WrappedText $g $subtitle $fontBody $muted 86 $y 880 58
    }

    $y += 45
    foreach ($block in $blocks) {
        if ($block.Type -eq "pill") {
            Draw-RoundedRect $g $soft 82 $y 916 78 22
            $g.DrawString($block.Text, $fontBodyBold, $black, 118, ($y + 13))
            $y += 104
        } elseif ($block.Type -eq "accent") {
            Draw-RoundedRect $g $accent 82 $y 916 92 24
            $g.DrawString($block.Text, $fontBodyBold, $white, 118, ($y + 18))
            $y += 118
        } elseif ($block.Type -eq "split") {
            Draw-RoundedRect $g $soft 82 $y 430 360 28
            Draw-RoundedRect $g $soft 568 $y 430 360 28
            $g.DrawString($block.LeftTitle, $fontBodyBold, $black, 122, ($y + 38))
            $leftY = $y + 110
            foreach ($item in $block.LeftItems) {
                $leftY = Draw-WrappedText $g $item $fontSmall $muted 126 $leftY 330 46
                $leftY += 6
            }
            $g.DrawString($block.RightTitle, $fontBodyBold, $black, 608, ($y + 38))
            $rightY = $y + 110
            foreach ($item in $block.RightItems) {
                $rightY = Draw-WrappedText $g $item $fontSmall $muted 612 $rightY 330 46
                $rightY += 6
            }
            $y += 400
        } else {
            $y = Draw-WrappedText $g $block.Text $fontBody $black 92 $y 880 61
            $y += 22
        }
    }

    $g.DrawLine($linePen, 82, 980, 998, 980)
    $g.DrawString($footer, $fontTiny, $muted, 82, 1000)

    $file = Join-Path $OutputDir ("day2_card_{0:D2}.png" -f $index)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)

    $g.Dispose()
    $bmp.Dispose()
    return $file
}

$cards = @(
    @{
        Eyebrow="文科生学 AI Day2"; Accent="#E85D4A"; Footer="Day2｜Codex 不是另一个聊天框"; Title="Codex 为什么不只是聊天机器人？"; Subtitle="我不写代码，也开始理解 AI Agent 了"; Blocks=@()
    },
    @{
        Eyebrow="先抛一个问题"; Accent="#2F7D75"; Footer="普通人学 AI，先从真实疑惑开始"; Title="我一开始也很疑惑"; Subtitle="我又不是程序员，真的需要学 AI Agent 吗？"; Blocks=@(
            @{Type="text"; Text="[卡住] 不写代码`n[电脑] 不做计算机工作`n[疑问] 那这个《更高级的 AI》，和我有什么关系？"}
        )
    },
    @{
        Eyebrow="我现在的理解"; Accent="#D99A2B"; Footer="不是谁更高级，而是协作方式不同"; Title="ChatGPT 和 Codex 的差别"; Subtitle="一个更像陪我想，一个更像陪我做"; Blocks=@(
            @{Type="split"; LeftTitle="[想] ChatGPT"; LeftItems=@("陪你想", "解释概念", "给建议", "帮你把话说明白"); RightTitle="[做] AI Agent / Codex"; RightItems=@("进到任务现场", "读文件 / 看路径", "拆步骤", "执行和验证")}
        )
    },
    @{
        Eyebrow="一个很小的例子"; Accent="#6B6FCF"; Footer="小问题不重要，重要的是它让我看懂了差别"; Title="WPS 提示 C 盘满了"; Subtitle="但我的文件明明在 D 盘"; Blocks=@(
            @{Type="text"; Text="这件事很小，甚至有点《小题大作》。"},
            @{Type="pill"; Text="我卡住的不是《怎么清理》"},
            @{Type="text"; Text="而是：`n? 问题到底出在哪`n? 哪些文件能动`n? 哪些东西不能乱删`n? 下一步该先查什么"}
        )
    },
    @{
        Eyebrow="这件小事让我意识到"; Accent="#C6517A"; Footer="AI Agent 的价值，有时就在这些说不清的小麻烦里"; Title="AI Agent 不只适合《大项目》"; Subtitle="也适合那些碎、烦、说不清的问题"; Blocks=@(
            @{Type="text"; Text="它的价值不是《替我一键解决》。"},
            @{Type="accent"; Text="而是陪我把问题拆开"},
            @{Type="text"; Text="先判断原因，再决定下一步，最后去验证结果。"}
        )
    },
    @{
        Eyebrow="我真正想记住的是"; Accent="#2E8B57"; Footer="工具会越来越强，人更要练判断"; Title="AI 时代重要的能力"; Subtitle="可能不是人人都会写代码"; Blocks=@(
            @{Type="pill"; Text="· 发现需求"},
            @{Type="pill"; Text="· 说清需求"},
            @{Type="pill"; Text="· 判断结果"},
            @{Type="pill"; Text="· 决定方向"}
        )
    },
    @{
        Eyebrow="Day2 的结论"; Accent="#1E6EA8"; Footer="下一篇：我把竞品分析做成了一个 skill"; Title="文科生不一定要会写代码"; Subtitle="但要学会和会执行的 AI 协作"; Blocks=@(
            @{Type="text"; Text="我还在 0 基础阶段，也没完全想明白。"},
            @{Type="text"; Text="但我开始觉得：Codex 不只是一个聊天机器人。"},
            @{Type="accent"; Text="它更像一种新的协作方式"},
            @{Type="text"; Text="Day3 我想继续记录：怎么把一个工作场景，变成可复用的 skill。"}
        )
    }
)

$files = @()
for ($i = 0; $i -lt $cards.Count; $i++) {
    $card = $cards[$i]
    $files += Save-Card ($i + 1) $card.Eyebrow $card.Title $card.Subtitle $card.Blocks $card.Accent $card.Footer
}

$files | ForEach-Object { Write-Output $_ }

