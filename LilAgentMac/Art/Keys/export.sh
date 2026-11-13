#!/bin/zsh
# Rasterizes the keycap SVGs in svg-keys-type-along/ into the PNGs the app bundles.
# Chrome is used because the SVGs rely on blur filters and masks that CoreSVG drops.
#
# The art has one accent colour (#7E6345) and every gradient, blur and blend in it is linear in that
# colour, so each key is rendered twice — accent as black (-0) and as white (-1) — and the app rebuilds
# any accent exactly as  pixel = key-0 + (key-1 - key-0) * accent.
set -euo pipefail
here=${0:A:h}
src=${here}/../../../svg-keys-type-along
out=${here}/../../LilAgent/Resources/Keys
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
size=192
tmp=$(mktemp -d)
trap 'rm -rf $tmp' EXIT
rm -rf $out && mkdir -p $out

# Blank cap: the A key with its letter layers removed, for keys without art (digits, accented letters).
awk '/filter="url\(#filter8_/{skip=1} /^<defs>/{skip=0} !skip' $src/A-key.svg > $tmp/blank-key.svg

render() {
  local svg=$1 name=$2 variant accent
  for variant accent in 0 '#000000' 1 '#FFFFFF'; do
    sed "s/#7[Ee]6345/$accent/g" $svg > $tmp/key.svg
    print "<html><body style='margin:0;background:transparent'><img src='file://$tmp/key.svg' style='width:${size}px;height:${size}px;display:block'></body></html>" > $tmp/page.html
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
      --default-background-color=00000000 --window-size=$size,$size --screenshot=$out/key-$name-$variant.png file://$tmp/page.html >/dev/null 2>&1
  done
}

for f in $src/*-key.svg; do render ${f:A} ${${f:t}%-key.svg}; done
render $tmp/blank-key.svg blank
print "exported $(ls $out | wc -l | tr -d ' ') images to ${out:A}"
