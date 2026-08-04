# emoji-list.txt에 적힌 이모지를 fluent-emoji 원본에서 찾아 3d/·flat/ 폴더로 평평하게 복사하는 스크립트
param(
  [string]$Source = 'D:\Project\02_Content_Writing\05_Assets\02_fluent-emoji\assets'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$utf8 = New-Object System.Text.UTF8Encoding $false

if (-not (Test-Path $Source)) { throw "원본 폴더 없음: $Source" }

# 1. 원본 1,595개 폴더의 metadata.json을 읽어 코드포인트 → 폴더 색인을 만든다
$index = @{}
foreach ($dir in Get-ChildItem $Source -Directory) {
  $metaPath = Join-Path $dir.FullName 'metadata.json'
  if (-not (Test-Path $metaPath)) { continue }
  $meta = [IO.File]::ReadAllText($metaPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
  $key = ($meta.unicode -replace 'fe0f', '' -replace '\s', '')
  if ($key -and -not $index.ContainsKey($key)) {
    $index[$key] = [pscustomobject]@{ Dir = $dir.FullName; Cldr = $meta.cldr }
  }
}

# 2. 목록을 읽어 3D PNG와 Flat SVG를 케밥케이스 이름으로 복사한다
$dst3d = Join-Path $root '3d'
$dstFlat = Join-Path $root 'flat'
New-Item -ItemType Directory -Force $dst3d, $dstFlat | Out-Null

$manifest = @()
$missing = @()

foreach ($line in [IO.File]::ReadAllLines((Join-Path $root 'emoji-list.txt'), [Text.Encoding]::UTF8)) {
  $emoji = $line.Trim()
  if (-not $emoji) { continue }

  $cps = @()
  for ($i = 0; $i -lt $emoji.Length; $i++) {
    if ([char]::IsHighSurrogate($emoji[$i])) {
      $cps += [char]::ConvertToUtf32($emoji[$i], $emoji[$i + 1]); $i++
    } else { $cps += [int]$emoji[$i] }
  }
  $key = ($cps | ForEach-Object { $_.ToString('x') }) -join '' -replace 'fe0f', ''

  if (-not $index.ContainsKey($key)) { $missing += "$emoji (U+$key)"; continue }

  $hit = $index[$key]
  $name = ($hit.Cldr.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')

  # 피부색 변형이 있는 이모지는 Default 하위에 3D/Flat이 들어 있다
  $base = $hit.Dir
  if (-not (Test-Path (Join-Path $base '3D'))) { $base = Join-Path $base 'Default' }

  $png = Get-ChildItem (Join-Path $base '3D') -Filter *.png -ErrorAction SilentlyContinue | Select-Object -First 1
  $svg = Get-ChildItem (Join-Path $base 'Flat') -Filter *.svg -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($png) { Copy-Item $png.FullName (Join-Path $dst3d "$name.png") -Force }
  if ($svg) { Copy-Item $svg.FullName (Join-Path $dstFlat "$name.svg") -Force }

  $manifest += [pscustomobject]@{
    emoji = $emoji
    name  = $name
    cldr  = $hit.Cldr
    png   = [bool]$png
    svg   = [bool]$svg
  }
}

$json = $manifest | ConvertTo-Json -Depth 3
[IO.File]::WriteAllText((Join-Path $root 'manifest.json'), $json, $utf8)

Write-Output "복사 완료: $($manifest.Count)종 (3D $(($manifest | Where-Object png).Count) / Flat $(($manifest | Where-Object svg).Count))"
if ($missing) { Write-Output "원본에서 못 찾음: $($missing -join ', ')" }
