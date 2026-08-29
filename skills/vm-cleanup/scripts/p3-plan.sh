#!/usr/bin/env bash

set -u

usage() {
  cat <<'EOF'
Usage:
  bash p3-plan.sh --workspace-root ABSOLUTE_PATH --manifest ABSOLUTE_PATH

Creates a read-only Phase 3 candidate manifest for Claude Desktop Cowork. The
manifest must be a new file in the mounted workspace audit directory. Candidate
discovery excludes Cowork's /sessions/*/mnt host-filesystem mount trees.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

canonical_dir() {
  local target=$1
  (cd -P -- "$target" 2>/dev/null && pwd -P)
}

sha256_file() {
  local target=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$target" | awk 'NR == 1 { print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$target" | awk 'NR == 1 { print $1 }'
  else
    return 1
  fi
}

workspace_root=''
manifest=''

while (($# > 0)); do
  case "$1" in
    --workspace-root)
      (($# >= 2)) || die '--workspace-root requires a value'
      workspace_root=$2
      shift 2
      ;;
    --manifest)
      (($# >= 2)) || die '--manifest requires a value'
      manifest=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$workspace_root" ]] || die '--workspace-root is required'
[[ -n "$manifest" ]] || die '--manifest is required'
[[ "$workspace_root" = /* ]] || die 'workspace root must be an absolute path'
[[ "$manifest" = /* ]] || die 'manifest path must be an absolute path'
[[ -d "$workspace_root" ]] || die 'workspace root does not exist'
[[ ! -L "$workspace_root" ]] || die 'workspace root must not be a symbolic link'

workspace_real=$(canonical_dir "$workspace_root") || die 'cannot resolve workspace root'
case "$workspace_real/" in
  /sessions/*/mnt/*/) ;;
  *) die 'workspace root must be inside a Cowork /sessions/<session>/mnt/ mount' ;;
esac
manifest_parent=$(dirname -- "$manifest")
expected_manifest_parent="$workspace_real/.vm-disk-cleanup/audit"
[[ "$manifest_parent" == "$expected_manifest_parent" ]] ||
  die 'manifest must be a direct child of <workspace>/.vm-disk-cleanup/audit'
[[ "$manifest" != *[[:cntrl:]]* ]] || die 'manifest path contains a control character'

audit_root="$workspace_real/.vm-disk-cleanup"
if [[ -L "$audit_root" ]]; then
  die '.vm-disk-cleanup must not be a symbolic link'
elif [[ -e "$audit_root" && ! -d "$audit_root" ]]; then
  die '.vm-disk-cleanup exists but is not a directory'
elif [[ ! -d "$audit_root" ]]; then
  mkdir -- "$audit_root" || die 'cannot create .vm-disk-cleanup directory'
fi

if [[ -L "$expected_manifest_parent" ]]; then
  die 'audit directory must not be a symbolic link'
elif [[ -e "$expected_manifest_parent" && ! -d "$expected_manifest_parent" ]]; then
  die 'audit path exists but is not a directory'
elif [[ ! -d "$expected_manifest_parent" ]]; then
  mkdir -- "$expected_manifest_parent" || die 'cannot create audit directory'
fi

manifest_parent_real=$(canonical_dir "$expected_manifest_parent") || die 'cannot resolve manifest directory'
[[ "$manifest_parent_real" == "$expected_manifest_parent" ]] ||
  die 'manifest directory resolved outside the expected workspace path'

manifest_real="$manifest_parent_real/$(basename -- "$manifest")"
[[ ! -e "$manifest_real" ]] || die 'refusing to overwrite an existing manifest'

[[ -d /sessions ]] || die 'Cowork /sessions root is unavailable'
[[ ! -L /sessions ]] || die 'Cowork /sessions root must not be a symbolic link'
sessions_root=$(canonical_dir /sessions) || die 'cannot resolve Cowork /sessions root'
[[ "$sessions_root" == /sessions ]] || die 'Cowork /sessions root resolved unexpectedly'

umask 077
temp_base="$manifest_parent_real/.vm-cleanup-p3-plan.$$"
candidates_file="$temp_base.candidates"
errors_file="$temp_base.errors"
body_file="$temp_base.body"

cleanup_temp() {
  rm -f -- "$candidates_file" "$errors_file" "$body_file"
}
trap cleanup_temp EXIT
: >"$candidates_file" || die 'cannot create candidate scratch file'
: >"$errors_file" || die 'cannot create scan-error scratch file'
: >"$body_file" || die 'cannot create manifest scratch file'

scan_complete=true
if ! find -P "$sessions_root" \
  \( -path '/sessions/*/mnt' -o -path '/sessions/*/mnt/*' \) -prune -o \
  -type d \( -name node_modules -o -name .next -o -name dist -o -name build \) \
  -print0 -prune >>"$candidates_file" 2>>"$errors_file"; then
  scan_complete=false
fi

global_root=''
if [[ -n "${HOME:-}" ]]; then
  requested_global_root="${HOME}/.npm-global/lib/node_modules"
  if [[ -L "$requested_global_root" ]]; then
    printf 'Global npm root is a symbolic link and was refused: %s\n' "$requested_global_root" >>"$errors_file"
    scan_complete=false
  elif [[ -d "$requested_global_root" ]]; then
    global_root=$(canonical_dir "$requested_global_root") || {
      printf 'Cannot resolve global npm root: %s\n' "$requested_global_root" >>"$errors_file"
      scan_complete=false
    }
  fi
fi
if [[ -n "$global_root" ]]; then
  if ! find -P "$global_root" -mindepth 1 -maxdepth 1 -type d -print0 >>"$candidates_file" 2>>"$errors_file"; then
    scan_complete=false
  fi
fi

printf 'category\tsize_bytes\tstatus\tcanonical_path\n' >"$body_file"
declare -A seen=()
candidate_count=0

while IFS= read -r -d '' candidate; do
  if [[ "$candidate" == *[[:cntrl:]]* ]]; then
    printf 'Unsupported control character in candidate path: %q\n' "$candidate" >>"$errors_file"
    scan_complete=false
    continue
  fi
  if [[ -L "$candidate" ]]; then
    printf 'Symbolic-link candidate refused: %s\n' "$candidate" >>"$errors_file"
    scan_complete=false
    continue
  fi
  canonical=$(canonical_dir "$candidate" 2>>"$errors_file") || {
    scan_complete=false
    continue
  }
  case "$canonical/" in
    /sessions/*/mnt/*/)
      printf 'Mounted host-workspace candidate refused: %s\n' "$canonical" >>"$errors_file"
      scan_complete=false
      continue
      ;;
  esac
  [[ -z "${seen[$canonical]+x}" ]] || continue
  seen[$canonical]=1

  if [[ -n "$global_root" && "$canonical" == "$global_root"/* ]]; then
    category='global-npm-package'
  else
    case "$canonical" in
      */node_modules) category='node_modules' ;;
      */.next) category='build-.next' ;;
      */dist) category='build-dist' ;;
      */build) category='build-build' ;;
      *)
        printf 'Unclassified candidate refused: %s\n' "$canonical" >>"$errors_file"
        scan_complete=false
        continue
        ;;
    esac
  fi

  size_kib=$(du -sk -- "$canonical" 2>>"$errors_file" | awk 'NR == 1 { print $1 }')
  if [[ ! "$size_kib" =~ ^[0-9]+$ ]]; then
    size_bytes='UNKNOWN'
    status='SIZE_ERROR'
    scan_complete=false
  else
    size_bytes=$((size_kib * 1024))
    status='CANDIDATE'
  fi
  printf '%s\t%s\t%s\t%s\n' "$category" "$size_bytes" "$status" "$canonical" >>"$body_file"
  ((candidate_count += 1))
done <"$candidates_file"

if [[ -s "$errors_file" ]]; then
  scan_complete=false
fi

{
  printf '# vm-disk-cleanup Phase 3 candidate manifest\n'
  printf '# format_version: 1\n'
  printf '# generated_at_utc: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  printf '# workspace_root: %s\n' "$workspace_real"
  printf '# scan_complete: %s\n' "$scan_complete"
  printf '# candidate_count: %d\n' "$candidate_count"
  printf '# scan_root: %s (host mount trees pruned)\n' "$sessions_root"
  if [[ -s "$errors_file" ]]; then
    printf '# scan_errors_begin\n'
    sed 's/^/# /' "$errors_file"
    printf '# scan_errors_end\n'
  fi
  cat "$body_file"
} >"$manifest_real" || die 'cannot write manifest'

manifest_sha256=$(sha256_file "$manifest_real") ||
  die 'cannot compute manifest SHA-256; Phase 3 must remain blocked'
[[ "$manifest_sha256" =~ ^[0-9a-fA-F]{64}$ ]] ||
  die 'invalid manifest SHA-256 result; Phase 3 must remain blocked'

printf 'Manifest: %s\n' "$manifest_real"
printf 'SHA-256: %s\n' "$manifest_sha256"
printf 'Candidates: %d\n' "$candidate_count"
printf 'Scan complete: %s\n' "$scan_complete"
cat "$body_file"

if [[ "$scan_complete" != true ]]; then
  printf 'ERROR: scan was incomplete; Phase 3 must remain blocked. See the manifest.\n' >&2
  exit 2
fi
