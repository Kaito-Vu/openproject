#!/bin/bash
# Assemble /rootfs for gcr.io/distroless/base-debian13 from the Debian runtime stage:
# Ruby/node, the external tools OpenProject shells out to, and exactly the shared
# libraries they link against (resolved with ldd). Package metadata is written to
# status.d so CVE scanners still see what was copied.
set -euo pipefail

ROOT=/rootfs
LIST=$(mktemp)
mkdir -p "$ROOT"

apt-get update -qq
apt-get install -yq --no-install-recommends busybox-static

# distroless/base-debian13 is merged-usr: /bin, /lib, /lib64, /sbin -> usr/*. Only ever
# write canonical /usr/... paths so the final COPY never replaces those symlinks.
canon() { echo "$(readlink -f "$(dirname "$1")")/$(basename "$1")"; }

# Copy a path plus every symlink hop leading to the real file.
grab() {
  local p t
  p=$(canon "$1")
  while [ -L "$p" ]; do
    cp -a --parents "$p" "$ROOT"
    t=$(readlink "$p")
    case $t in
      /*) p=$(canon "$t") ;;
      *)  p=$(readlink -f "$(dirname "$p")/$(dirname "$t")")/$(basename "$t") ;;
    esac
  done
  cp -a --parents "$p" "$ROOT"
  echo "$p" >> "$LIST"
}

is_elf() { head -c4 "$1" 2>/dev/null | cmp -s - <(printf 'ELF'); }

grab_libs() {
  local lib
  ldd "$1" 2>/dev/null | awk '$2=="=>" && $3 ~ /^\//{print $3} $1 ~ /^\//{print $1}' |
    while read -r lib; do grab "$lib"; done
}

# Entire trees: everything in them is needed at runtime.
for dir in \
  /usr/local \
  /usr/lib/postgresql \
  /usr/lib/xeokit-metadata \
  /usr/share/tesseract-ocr \
  /usr/share/poppler \
  /usr/share/catdoc \
  /usr/share/unrtf \
  /usr/share/ImageMagick-7 \
  /usr/lib/file \
  /usr/share/misc/magic.mgc \
  /etc/ImageMagick-7 \
  /usr/lib/*/ImageMagick-7*; do
  [ -e "$dir" ] || continue
  grab "$dir"
done
# Individual tools invoked by name (see Open3 calls in app/ and lib/).
for tool in file convert magick identify pdftotext pdfunite tesseract catdoc catppt xls2csv unrtf; do
  path=$(command -v "$tool" || true)
  [ -n "$path" ] && grab "$path"
done

# bash for the docker/prod/* scripts; busybox only for the few utilities they and
# the app use (file/which/du/sleep...). No other applets are linked.
grab /usr/bin/bash
ln -s bash "$ROOT/usr/bin/sh"
cp /usr/bin/busybox "$ROOT/usr/bin/busybox"
echo /usr/bin/busybox >> "$LIST"
for applet in env rm mkdir cat cp mv ln ls chmod dirname basename sleep cut tr sed grep head tail which du id date touch timeout; do
  ln -s busybox "$ROOT/usr/bin/$applet"
done

# Shared libraries for every ELF we copied, plus native gem extensions in the app.
{
  while read -r f; do
    [ -d "$f" ] && find "$f" -type f -print || echo "$f"
  done < "$LIST"
  find /app/vendor/bundle -type f -name '*.so*'
} | while read -r f; do
  is_elf "$f" && grab_libs "$f" || true
done

# libjemalloc is only loaded through LD_PRELOAD, so ldd never reports it.
for lib in /usr/lib/*/libjemalloc.so.2; do grab "$lib"; done

# Runtime users, home and writable dirs owned by the app user (uid/gid 1000).
mkdir -p "$ROOT/etc" "$ROOT/home/$APP_USER" "$ROOT$APP_DATA_PATH" "$ROOT/tmp/op_uploaded_files"
printf 'root:x:0:0:root:/root:/bin/bash\napp:x:%s:%s::/home/app:/bin/bash\n' \
  "$(id -u "$APP_USER")" "$(id -g "$APP_USER")" > "$ROOT/etc/passwd"
printf 'root:x:0:\napp:x:%s:\n' "$(id -g "$APP_USER")" > "$ROOT/etc/group"
cp -a /home/$APP_USER/. "$ROOT/home/$APP_USER/"
chown -R "$APP_USER:$APP_USER" "$ROOT/home/$APP_USER" "$ROOT$APP_DATA_PATH" "$ROOT/tmp/op_uploaded_files"
chmod g+rwx "$ROOT$APP_DATA_PATH"
# COPY would otherwise replace distroless' /tmp (1777) with this dir's mode.
chmod 1777 "$ROOT/tmp"

# ld.so cache so /usr/local/lib (libruby) resolves exactly like in the Debian image.
mkdir -p "$ROOT/etc/ld.so.conf.d"
cp /etc/ld.so.conf "$ROOT/etc/"
cp /etc/ld.so.conf.d/*.conf "$ROOT/etc/ld.so.conf.d/"
ldconfig -r "$ROOT"

# Report copied Debian packages (dpkg db fragments) for SBOM / CVE scanners.
mkdir -p "$ROOT/var/lib/dpkg/status.d"
# dpkg -S prints "pkg1, pkg2:arch: path"; it exits non-zero for paths no package owns.
{ sort -u "$LIST" | xargs dpkg -S 2>/dev/null || true; } |
  sed 's/: \/.*//' | tr ',' '
' | sed 's/^ *//; s/:.*//' | sort -u |
  while read -r pkg; do
    dpkg-query -s "$pkg" > "$ROOT/var/lib/dpkg/status.d/$pkg"
  done

rm -f "$LIST"
