#!/usr/bin/env bash
# 티스카 굿즈 제작 가이드 — 글 빌드·검증·커밋·푸시 한 번에
# 사용:  bash _build/publish.sh "커밋 메시지"
#   1) perl _build/posts_build.pl  (글·홈·RSS·llms 가이드 구역)
#   2) perl _build/build.pl        (메뉴·바로가기·Q&A 링크·faq·sitemap·llms Q&A 구역)
#   3) 새 글 규칙 검사(통과 못 하면 커밋하지 않음)
#   4) git add / commit / push
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MSG="${1:-가이드 글 추가}"

echo "== 1) posts_build"
perl _build/posts_build.pl
echo "== 2) build (qa/items/cases/sitemap/llms)"
perl _build/build.pl

echo "== 3) 규칙 검사"
fail=0
# 오늘 추가·수정된 글만 검사(스테이징 전 변경분 + 신규 파일)
changed=$( { git diff --name-only -- posts/ ; git ls-files --others --exclude-standard -- posts/ ; } | grep -E '\.html$' | sort -u || true)
newfiles=$(git ls-files --others --exclude-standard -- posts/ | grep -E '\.html$' || true)
if [ -z "$changed" ]; then echo "변경된 글 없음"; fi
for f in $changed; do
  t=$(sed 's/<[^>]*>/ /g' "$f")
  bad=$(echo "$t" | grep -oE '판촉물|500개 단위|500개씩|받지 않|인력 부족|대응이 어렵|불가합니다|오유미|최저가|업계 1위|국내 유일' | sort -u | tr '\n' ' ' || true)
  # 옛 최소 수량(10·50·100·300개부터) 검사는 이번에 새로 추가된 글에만(기존 글의 나도메이커 소량 품목 표는 허용된 내용).
  # 나도메이커를 언급한 문장은 제외하고 검사한다.
  old=""
  if echo "$newfiles" | grep -qx "$f"; then
    old=$(echo "$t" | tr '.' '\n' | grep -viE '나도메이커|nadomaker' | grep -oE '(^|[^0-9~,])(10|50|100|300)개부터' | sort -u | tr '\n' ' ' || true)
  fi
  moq=$(echo "$t" | grep -c '500개부터' || true)
  # 분량(본문 공백 제외 글자 수, posts_build.pl 이 기록) — 새 글은 1,400자 이상이어야 함
  short=""
  if echo "$newfiles" | grep -qx "$f"; then
    slug=$(basename "$f" .html)
    chars=$(awk -F'\t' -v s="$slug" '$1==s{print $2}' _build/.last_build_chars.tsv 2>/dev/null || true)
    kind=$(awk -F'\t' -v s="$slug" '$1==s{print $3}' _build/.last_build_chars.tsv 2>/dev/null || true)
    min=1400; [ "$kind" = "case" ] && min=800   # 제작 사례 글은 800자 이상
    if [ -n "$chars" ] && [ "$chars" -lt "$min" ]; then short="분량 ${chars}자(<${min})"; fi
  fi
  if [ -n "$bad" ] || [ -n "$old" ] || [ "$moq" = "0" ] || [ -n "$short" ]; then
    echo "FAIL $f  금지어:[$bad] 옛수량:[$old] 500개부터:$moq $short"; fail=1
  else
    echo "ok   $f  (500개부터 ${moq}회)"
  fi
done
if python3 -c 'print(1)' 2>/dev/null | grep -q '^1$'; then   # 실제로 동작하는 python3 가 있을 때만(윈도우 스토어 스텁 제외)
  for f in $changed; do
    python3 - "$f" <<'PY' || fail=1
import re, sys, json, html
s = open(sys.argv[1], encoding='utf-8').read()
for m in re.finditer(r'<script type="application/ld\+json">(.*?)</script>', s, re.S):
    json.loads(m.group(1))
print("json-ld ok", sys.argv[1])
PY
  done
fi
if [ "$fail" != "0" ]; then echo "규칙 검사 실패 — 커밋하지 않음"; exit 1; fi

echo "== 4) 커밋·푸시"
git add -A
if git diff --cached --quiet; then echo "커밋할 변경 없음"; exit 0; fi
git -c user.name="${GIT_AUTHOR_NAME:-ohyoumeee-prog}" -c user.email="${GIT_AUTHOR_EMAIL:-ohyoumeee-prog@users.noreply.github.com}" commit -q -m "$MSG" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push origin HEAD:main
echo "완료: $(git log -1 --format='%h %s')"
