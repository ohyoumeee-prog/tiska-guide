#!/usr/bin/perl
# 티스카 굿즈 제작 가이드 — 제조사 홈페이지형 구성 생성기
# 사용:  perl _build/site_build.pl   (저장소 어느 위치에서 실행해도 됨)
# 순서:  perl _build/posts_build.pl && perl _build/build.pl && perl _build/site_build.pl
# 입력:  _src/cases_data.tsv(사례 사양), _src/case_queue.tsv(사례 블로그 글), cases/img·cases/thumb(사진), posts/*.html(가이드 글 제목)
# 출력:
#   1) cases/index.html        제작 사례 포트폴리오(카드 그리드 + 품목군 탭) — build.pl 이 만든 목록을 덮어씀
#   2) cases/{type}{no}.html   사례 상세(사진·제작 정보·제작 포인트·같은 사양으로 만드는 방법)
#   3) guide/index.html        주문 제작 가이드(HowTo)
#   4) about.html              회사 소개(사실은 _src/FACTS.md 기준)
#   5) contact.html            견적 문의 + 견적 요청서 작성기 — build.pl 4-4 결과를 덮어씀
#   6) index.html              <!-- quick:end --> 뒤에 <!-- site:start -->…<!-- site:end --> 블록
#   7) sitemap.xml             guide/ · cases/{type}{no}.html 추가(같은 loc 는 먼저 제거)
#   8) llms.txt                <!-- site:llms:start -->…<!-- site:llms:end --> 구역(파일 끝)
# 머리말(header) 마크업은 build.pl 의 nav() 와 글자 그대로 같아야 한다(실행 때 faq.html 과 비교해 다르면 멈춤).
# 문구 규칙: 최소 수량은 "메인 발주 500개부터"만. cases_data.tsv 의 '최소 수량' 열(옛 수치)은 쓰지 않는다.
use strict;
use warnings;
use utf8;
use open qw(:std :encoding(UTF-8));
use Encode qw(encode_utf8);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use POSIX qw(strftime);
use JSON::PP;

my $BASE = 'https://ohyoumeee-prog.github.io/tiska-guide/';
my $ROOT = dirname(dirname(__FILE__));
chdir $ROOT or die "cannot chdir $ROOT";

# 기준일: 페이지 내용을 정하는 입력 파일(사례 사양·FACTS·이 생성기)이 마지막으로 커밋된 날(KST).
# 실행 날짜를 쓰면 내용 변화 없이 날마다 페이지 170개 안팎과 sitemap lastmod 가 바뀌므로 피한다.
# 입력 파일에 커밋 안 된 변경이 있거나 git 을 쓸 수 없으면 오늘(KST).
my @DATE_SRC = ('_src/cases_data.tsv', '_src/FACTS.md', '_build/site_build.pl');
my $DATE_TS;
{
  my $files = join ' ', map { qq("$_") } @DATE_SRC;
  my $dirty = `git status --porcelain -- $files 2>&1`;
  if (defined $dirty && $? == 0 && $dirty !~ /\S/) {
    my $ct = `git log -1 --format=%ct -- $files 2>&1`;
    $DATE_TS = $1 if $? == 0 && defined $ct && $ct =~ /^(\d{9,})\s*$/;
  }
  $DATE_TS //= time;
}
my @KST = gmtime($DATE_TS + 9 * 3600);                   # Asia/Seoul (UTC+9, 서머타임 없음)
my $TODAY    = strftime('%Y-%m-%d', @KST);
my $TODAY_KO = sprintf('%d년 %d월 %d일', $KST[5] + 1900, $KST[4] + 1, $KST[3]);
my $ASOF     = "$TODAY_KO 기준";
my $EMAIL    = 'ttiska' . '@' . 'naver.com';
my $ORG_ID   = 'https://tiska.kr/#organization';
my $MOQ      = '메인 발주 500개부터';
my $NADO     = '500개 미만의 소량이 필요하면 자체 소량 제작 쇼핑몰 나도메이커(nadomaker.com)에서 제작할 수 있습니다.';

# ---------- 유틸 ----------
sub slurp { my $f = shift; open my $h, '<', $f or die "read $f: $!"; local $/; my $s = <$h>; close $h; $s =~ s/^\x{FEFF}//; $s =~ s/\r\n/\n/g; return $s; }
sub spew  { my ($f, $s) = @_; make_path(dirname($f)); open my $h, '>', $f or die "write $f: $!"; print $h $s; close $h; }
sub esc   { my $s = shift // ''; $s =~ s/&(?![a-zA-Z#0-9]+;)/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; return $s; }
sub urlenc { my $b = encode_utf8(shift); $b =~ s/([^A-Za-z0-9\-_.~])/sprintf('%%%02X', ord $1)/ge; return $b; }
sub cut   { my ($s, $n) = @_; return $s if length($s) <= $n; $s = substr($s, 0, $n); $s =~ s/\s+\S*$//; return "$s…"; }
sub trim  { my $s = shift // ''; $s =~ s/^\s+|\s+$//g; return $s; }
# 완결된 구절 단위로 붙이기(말줄임표 없음): 머리 + 가운데 구절들 + 꼬리를 $n 글자(공백 포함) 안에서.
# 가운데 구절은 순서대로 들어갈 때까지 넣고, 안 들어가는 구절은 ["이름", "값1, 값2"] 이면 값을 쉼표 단위로 줄여 본다.
sub fit_phrases {
  my ($n, $head, $tail, @mid) = @_;
  my $out = $head;
  my $room = sub { $n - length($out) - 1 - length($tail) };   # 구절 사이 공백 1자 포함
  for my $m (@mid) {
    my ($k, $v) = @$m;
    $v =~ s/[.\s]+$//;
    my $ph = "$k $v.";
    if (length($ph) + 1 <= $room->()) { $out .= " $ph"; next; }
    my @parts = split /\s*,\s*/, $v;
    while (@parts > 1) { pop @parts; my $t = "$k " . join(', ', @parts) . '.'; if (length($t) + 1 <= $room->()) { $out .= " $t"; last; } }
  }
  return length($out) + 1 + length($tail) <= $n ? "$out $tail" : (length($out) <= $n ? $out : $head);
}
my $JSON = JSON::PP->new->canonical(1)->allow_nonref;
sub jsonld { my $s = $JSON->encode(shift); $s =~ s{</}{<\\/}g; return $s; }
sub nospace_len { my $s = shift; $s =~ s{<script.*?</script>}{}gs; $s =~ s/<[^>]+>//g; $s =~ s/&[a-z#0-9]+;/x/gi; $s =~ s/\s+//g; return length $s; }
# 받침에 따라 조사 고르기: josa('볼마커', '은', '는')
sub josa {
  my ($w, $a, $b) = @_;
  my $t = $w; $t =~ s/[\s)\]」』"'”’.]+$//;
  my $c = substr($t, -1); my $o = ord($c // ' ');
  return (($o - 0xAC00) % 28) ? $a : $b if $o >= 0xAC00 && $o <= 0xD7A3;
  return $c =~ /[013678]/ ? $a : $b if $c =~ /\d/;
  return $c =~ /[lmnr]/i ? $a : $b if $c =~ /[a-z]/i;
  return $a;
}
# JPEG 크기(가로, 세로) — 코어 모듈만 사용
my %JPG;
sub jpeg_size {
  my $f = shift;
  return @{ $JPG{$f} } if $JPG{$f};
  open my $h, '<:raw', $f or return (0, 0);
  local $/; my $d = <$h>; close $h;
  my ($i, $n) = (2, length $d);
  while ($i + 9 < $n) {
    if (ord(substr($d, $i, 1)) != 0xFF) { $i++; next; }
    my $m = ord(substr($d, $i + 1, 1));
    if ($m == 0xFF) { $i++; next; }
    if ($m == 0xD8 || $m == 0x01 || ($m >= 0xD0 && $m <= 0xD7)) { $i += 2; next; }
    my $len = unpack('n', substr($d, $i + 2, 2));
    if ($m >= 0xC0 && $m <= 0xCF && $m != 0xC4 && $m != 0xC8 && $m != 0xCC) {
      my ($hh, $ww) = unpack('nn', substr($d, $i + 5, 4));
      $JPG{$f} = [$ww, $hh]; return ($ww, $hh);
    }
    $i += 2 + $len;
  }
  $JPG{$f} = [0, 0]; return (0, 0);
}
sub days { my $d = shift // ''; return $d =~ /(\d+)주/ ? $1 * 7 : $d =~ /(\d+)일/ ? $1 : 0; }   # build.pl days() 와 같음
sub wh { my ($w, $h) = @_; return $w && $h ? qq( width="$w" height="$h") : ''; }

# ---------- 공통 조각(build.pl 의 nav()·footer()·head() 와 같은 마크업) ----------
sub nav {
  my ($p, $cur) = @_;
  my @items = (['index.html', '가이드', 'guide'], ['items/', '품목', 'items'], ['cases/', '제작 사례', 'cases'], ['guide/', '주문 제작 가이드', 'howto'], ['faq.html', '자주 묻는 질문', 'faq'], ['tools/schedule.html', '일정 계산기', 'tool'], ['about.html', '회사 소개', 'about']);
  my $s = qq(<header class="site"><div class="wrap"><a class="brand" href="${p}index.html">티스카 <span>굿즈 제작 가이드</span></a><nav aria-label="주 메뉴">);
  for (@items) { $s .= qq(<a href="$p$_->[0]") . ($cur eq $_->[2] ? ' aria-current="page"' : '') . qq(>$_->[1]</a>); }
  return $s . qq(<a href="https://tiska.kr" rel="noopener">tiska.kr</a><a class="nav-cta" href="${p}contact.html") . ($cur eq 'contact' ? ' aria-current="page"' : '') . qq(>견적 문의</a></nav></div></header>);
}
sub footer {
  my $p = shift;
  return qq(<footer class="site"><div class="wrap"><p><strong>주식회사 티스카</strong> · 굿즈·프로모션 상품 주문 제작(OEM/ODM) · 사업자등록번호 275-88-02236 · 대표 오의미</p><p>본사 서울특별시 성동구 아차산로17길 48, 성수 SKV1센터1 1515호 · 자체 공장 서울 중랑구 · 생산 네트워크 중국 광저우·이우</p><p>전화 <a href="tel:+82-2-930-8000">02-930-8000</a> · 이메일 <a href="mailto:$EMAIL">$EMAIL</a> · <a href="https://tiska.kr">tiska.kr</a> · 소량·빠른 제작 <a href="https://nadomaker.com">nadomaker.com</a> · <a href="https://www.instagram.com/tiska_office" rel="noopener">Instagram</a> · <a href="https://blog.naver.com/ttiska" rel="noopener">네이버 블로그</a></p><p>모든 숫자는 tiska.kr 공개 정보, $ASOF. · <a href="${p}llms.txt">llms.txt</a> · <a href="${p}rss.xml">RSS</a> · <a href="${p}sitemap.xml">사이트맵</a> · © 2026 주식회사 티스카</p></div></footer>);
}
sub head {
  my (%o) = @_;
  my $p = $o{p};
  my $og = $o{og} // "${BASE}og/default.png";
  my ($ow, $oh) = @{ $o{ogsize} // [1200, 630] };
  return <<"HTML";
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>@{[ esc($o{title}) ]}</title>
<meta name="description" content="@{[ esc($o{desc}) ]}">
<meta name="robots" content="index,follow,max-snippet:-1,max-image-preview:large">
<meta name="author" content="주식회사 티스카">
<link rel="canonical" href="$o{url}">
<link rel="alternate" type="application/rss+xml" title="티스카 굿즈 제작 가이드" href="${p}rss.xml">
<link rel="icon" href="${p}favicon.ico" sizes="32x32">
<link rel="icon" href="${p}favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="${p}apple-touch-icon.png">
<meta property="og:type" content="$o{ogtype}">
<meta property="og:site_name" content="티스카 굿즈 제작 가이드">
<meta property="og:locale" content="ko_KR">
<meta property="og:title" content="@{[ esc($o{title}) ]}">
<meta property="og:description" content="@{[ esc($o{desc}) ]}">
<meta property="og:url" content="$o{url}">
<meta property="og:image" content="$og">
<meta property="og:image:width" content="$ow">
<meta property="og:image:height" content="$oh">
<meta name="twitter:card" content="summary_large_image">
<link rel="stylesheet" href="${p}style.css">
<script type="application/ld+json">
$o{jsonld}
</script>
</head>
<body>
<a class="skip" href="#main">본문으로 건너뛰기</a>
HTML
}
sub page_end { my $p = shift; return "</main>\n" . footer($p) . "\n</body>\n</html>\n"; }

# 구조화 데이터 — Organization
my %ORG = ('@type' => 'Organization', '@id' => $ORG_ID, name => '주식회사 티스카', alternateName => ['TISKA', '티스카'], url => 'https://tiska.kr',
  logo => { '@type' => 'ImageObject', url => "${BASE}logo.png", width => 512, height => 512 });   # build.pl $ORG_JSON 과 같은 필드
my $ADDR = { '@type' => 'PostalAddress', streetAddress => '아차산로17길 48, 성수 SKV1센터1 1515호', addressLocality => '성동구', addressRegion => '서울특별시', addressCountry => 'KR' };
my %ORG_CONTACT = ('@type' => 'Organization', '@id' => $ORG_ID, name => '주식회사 티스카', alternateName => ['TISKA', '티스카'], url => 'https://tiska.kr',
  telephone => '+82-2-930-8000', email => $EMAIL, address => $ADDR,
  contactPoint => [{ '@type' => 'ContactPoint', contactType => 'sales', telephone => '+82-2-930-8000', email => $EMAIL, availableLanguage => ['ko'], areaServed => ['KR', 'JP', 'CN', 'US', 'ID'] }]);   # build.pl 4-4 문의 페이지와 같은 필드
my %ORG_ABOUT = (%ORG_CONTACT,
  logo => { '@type' => 'ImageObject', url => "${BASE}logo.png", width => 512, height => 512 },
  description => '굿즈·프로모션 상품 주문 제작(OEM/ODM) 제조사. 콘서트 MD, 팬클럽 키트, 기업 웰컴키트, 골프 기념품을 디자인부터 샘플·양산·납품까지 진행. 서울 중랑구 자체 공장과 중국 광저우·이우 생산 네트워크 운영.',
  foundingDate => '2022-03-01', taxID => '275-88-02236',
  knowsAbout => ['굿즈 제작', '콘서트 MD', '웰컴키트', '골프 기념품', 'OEM', 'ODM', '아크릴 키링', '에코백', '금속 뱃지'],
  brand => [{ '@type' => 'Brand', name => '나도메이커', url => 'https://nadomaker.com', sameAs => ['https://www.instagram.com/nadomaker'] }],
  sameAs => ['https://www.instagram.com/tiska_office', 'https://blog.naver.com/ttiska']);
sub crumb_json {
  my @c = @_; my $i = 0;
  return { '@type' => 'BreadcrumbList', itemListElement => [ map { $i++; { '@type' => 'ListItem', position => $i, name => $_->[0], item => $_->[1] } } @c ] };
}
sub graph { return jsonld({ '@context' => 'https://schema.org', '@graph' => [@_] }); }

# ---------- 품목군(build.pl 4-2 @ITEMS 의 정규식 그대로, 샘플·양산·예시는 FACTS 표) ----------
my @GROUPS = (
  ['acrylic-keyring', '아크릴·키링류', '1일', '7일', '아크릴 키링, 쉐이커 키링, 미러 키링, 응원부채, 맥세이프 카드지갑', qr/아크릴|쉐이커|미러 키링|부채|맥세이프|스탠드/],
  ['bag-pouch', '가방·파우치류', '1주', '20일', '에코백, 보스턴백, 백팩, 슈즈파우치, 보냉백, 타포린백, 리유저블백', qr/백|파우치|가방|짐색|토트|숄더/],
  ['metal-jewelry', '금속·주얼리류', '1주', '20일', '금속 뱃지, 볼마커, 디봇툴, 메달, 팔찌, 목걸이, 반지', qr/뱃지|볼마커|디봇|메달|팔찌|목걸이|반지/],
  ['fabric-apparel', '패브릭·의류류', '1주', '20일', '볼타월, 샤워가운, 담요, 양말, 팔토시, 스카프, 장갑', qr/타올|타월|양말|장갑(?! 케이스)|담요|스카프|팔토시|가운|티셔츠|후드|스크런치|스베리/],
  ['silicone', '실리콘류', '1주', '20일', '실리콘 키링, 피규어, 퍼터키퍼, 응원봉 참', qr/실리콘|퍼터키퍼|피규어|참/],
  ['golf-accessory', '골프 소품·커버류', '1주', '20일', '헤드커버, 아이언커버, 얼라이먼트 스틱 커버, 항공커버, 네임택', qr/커버|네임택/],
  ['package-set', '패키지·세트류', '1주', '14일', '싸바리 기프트박스, 트로피 패키지, 웰컴키트, 골프공 세트', qr/패키지|기프트|웰컴키트|골프공|박스/],
  ['stationery-print', '문구·인쇄류', '1주', '14일', '스티커 세트, 마우스패드, 카드 패키지, 명함 카드지갑', qr/스티커|마우스패드|명함|카드 패키지|문구/],
  ['plush-doll', '봉제·인형류', '1주', '20일', '봉제 인형, 인형키링, 쿠션, 러그, 미니어처', qr/인형|쿠션|러그|미니어처/],
  ['others', '기타(텀블러·우산 등)', '2주', '20일', '텀블러, 우산, 여행 오거나이저, 일회용 필름카메라', qr/텀블러(?! 슬리브)|(?<!초록)우산|오거나이저|카메라|와인잔|보틀/],
);
my %G; my @GORDER;
for (@GROUPS) { my %g; @g{qw(slug name s pd ex re)} = @$_; $G{$g{slug}} = \%g; push @GORDER, $g{slug}; }
$G{project} = { slug => 'project', name => '프로젝트 MD 세트', s => '1일~2주', pd => '7~20일', ex => '콘서트·팬미팅·드라마 공식 MD 여러 품목 묶음' };
my @TABS = (@GORDER, 'project');

# 관련 가이드 글(파일이 있을 때만 링크)
my %GPOSTS = (
  'acrylic-keyring'  => ['acrylic-keyring-structure-guide', 'kpop-concert-md-production'],
  'bag-pouch'        => ['cosmetics-pouch-production-guide', 'cosmetics-pouch-print-method-comparison', 'ecobag-production-guide'],
  'metal-jewelry'    => ['metal-goods-plating-color-guide', 'year-end-awards-trophy-medal-goods'],
  'fabric-apparel'   => ['running-crew-group-goods'],
  'silicone'         => ['goods-moq-by-item'],
  'golf-accessory'   => ['golf-gift-moq-and-lead-time'],
  'package-set'      => ['year-end-corporate-gift-production', 'cosmetics-brand-launch-popup-goods-kit'],
  'stationery-print' => ['design-file-preparation'],
  'plush-doll'       => ['nonprofit-campaign-goods'],
  'others'           => ['goods-moq-by-item'],
  'project'          => [],
);
my %TITLE;
sub post_title {
  my $slug = shift;
  return $TITLE{$slug} if exists $TITLE{$slug};
  my $f = "posts/$slug.html";
  return $TITLE{$slug} = undef unless -f $f;
  my ($h1) = slurp($f) =~ m{<h1>(.*?)</h1>}s;
  return $TITLE{$slug} = $h1 // $slug;
}
sub post_links {   # [slug, 제목] 목록 — 파일 있는 것만, 중복 제거
  my %seen; my @out;
  for my $s (@_) { next if $seen{$s}++; my $t = post_title($s); push @out, [$s, $t] if defined $t; }
  return @out;
}

# ---------- 사례 데이터 ----------
# 금지어 치환: 사례 열 값은 글자 그대로 쓰되, 금지어 '판촉'만 FACTS 의 대체어로 바꾼다(원본 TSV 는 수정하지 않음).
sub norm_word { my $s = shift // ''; $s =~ s/판촉물/프로모션 제품/g; $s =~ s/판촉/프로모션/g; return $s; }
# 품목군 판정: ① 이름이 분명한 골프 커버류(항공커버 등)는 먼저 골프 소품·커버류
#             ② build.pl 4-2 @ITEMS 정규식(품목명에 첫 번째로 맞는 품목군)
#             ③ 어디에도 안 맞으면 FACTS 기준 보조 규칙: PVC·금형 성형 → 실리콘류, 키링·아크릴 → 아크릴·키링류, 슬리브 → 가방·파우치류
#             ④ 그래도 없으면 기타(텀블러·우산 등)
sub group_of {
  my ($name, $mat, $proc) = @_;
  return 'golf-accessory' if $name =~ /항공커버|헤드커버|아이언커버/;
  for my $g (@GORDER) { return $g if $name =~ $G{$g}{re}; }
  return 'silicone'        if $name =~ /PVC/i || $mat =~ /PVC/i || $proc =~ /금형 성형/;
  return 'acrylic-keyring' if $name =~ /키링|아크릴/ || $mat =~ /아크릴/;
  return 'bag-pouch'       if $name =~ /슬리브/;
  return 'others';
}
# 카드 표시용: 품목명이 클라이언트명(괄호 앞 이름, 「」 안 이름 포함)으로 시작하면 그 부분을 뺀다
sub short_name {
  my ($client, $name) = @_;
  return $name if $client eq '';
  my @cand = ($client);
  (my $base = $client) =~ s/\s*\([^()]*\)\s*$//; push @cand, $base;
  push @cand, $1 if $client =~ /「(.+?)」/;
  for my $k (sort { length($b) <=> length($a) } grep { $_ ne '' } @cand) {
    next unless index($name, "$k ") == 0;
    my $rest = trim(substr($name, length($k) + 1));
    return $rest if $rest ne '';
  }
  return $name;
}
my (@CASES, @SKIPPED);
{
  my @lines = grep { /\S/ } split /\n/, slurp('_src/cases_data.tsv');
  my @h = split /\t/, shift @lines;
  for my $l (@lines) {
    my @v = split /\t/, $l, -1; my %r; @r{@h} = map { norm_word(trim($_)) } @v;
    my $type = $r{type} // ''; my $no = $r{no} // '';
    die "cases_data.tsv: type/no 오류: $l" unless $type =~ /^[pf]$/ && $no =~ /^\d+$/;
    my $client = $r{'클라이언트'} // '';
    my $name = $type eq 'f' ? ($r{'프로젝트'} // '') : ($r{'품목'} // '');
    if ($name eq '') { push @SKIPPED, "$type$no"; next; }   # 품목(또는 프로젝트)이 없는 행: 페이지를 만들 수 없음
    my %c = (%r, type => $type, no => $no, id => "$type$no", client => $client, name => $name);
    if ($type eq 'f') { $c{group} = 'project'; }
    else { $c{group} = group_of($name, $r{'소재'} // '', $r{'가공'} // ''); }
    my @imgs;
    for my $f (sort { ($a =~ /_(\d+)\.jpg$/)[0] <=> ($b =~ /_(\d+)\.jpg$/)[0] } glob("cases/img/${type}_${no}_*.jpg")) {
      my ($nn) = $f =~ /_(\d+)\.jpg$/ or next;
      my $b = "${type}_${no}_$nn.jpg";
      my ($w, $hh) = jpeg_size($f);
      my $t = "cases/thumb/$b";
      my ($tw, $th) = -f $t ? jpeg_size($t) : (0, 0);
      push @imgs, { file => $b, w => $w, h => $hh, thumb => (-f $t ? 1 : 0), tw => $tw, th => $th };
    }
    $c{imgs} = \@imgs;
    $c{label} = $client ne '' ? "$client $name" : $name;
    $c{short} = short_name($client, $name);                     # 카드용: 품목명 앞의 클라이언트명 반복 제거
    $c{slabel} = $client ne '' ? "$client $c{short}" : $name;
    $c{h1} = $type eq 'f' ? "$c{label} 공식 MD 제작 사례" : "$c{label} 제작 사례";
    $c{url} = "${BASE}cases/$c{id}.html";
    $c{tiska} = $type eq 'p' ? "https://tiska.kr/board/magazine/read.html?no=$no&board_no=5" : "https://tiska.kr/board/gallery/read.html?no=$no&board_no=8";
    push @CASES, \%c;
  }
}
my %BYG; push @{ $BYG{ $_->{group} } }, $_ for @CASES;
my $NC  = scalar @CASES;
my $NCP = scalar grep { $_->{type} eq 'p' } @CASES;
my $NCF = $NC - $NCP;

# 이 사례를 다룬 블로그 글(_src/case_queue.tsv status=published)
my %CASEPOST;
if (-f '_src/case_queue.tsv') {
  my @lines = grep { /\S/ } split /\n/, slurp('_src/case_queue.tsv');
  my @h = split /\t/, shift @lines;
  for my $l (@lines) {
    my @v = split /\t/, $l, -1; my %r; @r{@h} = map { trim($_) } @v;
    next unless ($r{status} // '') eq 'published' && $r{slug} && -f "posts/$r{slug}.html";
    push @{ $CASEPOST{ ($r{type} // '') . ($r{no} // '') } }, $r{slug};
  }
}

# ---------- 공통 문장 ----------
my @STEPS = (   # FACTS 진행 순서(6단계)
  ['1:1 미팅·문의 접수', '품목·수량·예산·납기를 확인하고 전담 PM이 배정됩니다.', '품목 목록, 수량과 사이즈, 예산과 용도, 사용 일정', '품목·수량 확정 후 안내'],
  ['기획·디자인(무료 시안)', '내부 디자인팀이 레퍼런스를 바탕으로 무료 시안을 만듭니다.', '로고·캐릭터 원본 파일(AI·PDF·PSD), 원하는 느낌의 레퍼런스 이미지', '품목·수량 확정 후 안내'],
  ['사양 설계·견적(수량 구간별 단가)', '소재·가공·규격·부자재를 정하고 수량 구간별 단가로 견적을 드립니다.', '검토할 수량 구간, 포장 방식, 납품 장소', '품목·수량 확정 후 안내'],
  ['디자인 확정·샘플 제작', '확정된 디자인으로 실물 샘플(프로토타입)을 만들어 색상·크기·마감을 확인합니다.', '승인 전 확인 항목(색상, 크기, 로고 위치, 부자재, 포장)', '샘플 1일~2주(품목군별)'],
  ['양산(승인 샘플 기준, QA/QC)', '승인된 샘플을 기준으로 생산하고 QA/QC를 거칩니다.', '승인 샘플 기준 유지(승인 뒤 변경은 일정에 영향)', '양산 7~20일(품목군별)'],
  ['검품·납품·사후관리', '검품 후 납품하고, 추가 생산 같은 사후 관리까지 전담 PM이 이어서 맡습니다.', '납품 주소, 받는 분, 분배·포장 요청', '품목·수량 확정 후 안내'],
);
my @STEPS_SHORT = (
  '문의: 이 페이지 주소와 함께 품목·수량·예산·납기를 알려 주세요.',
  '기획·디자인: 디자인팀이 무료 시안을 만듭니다.',
  '사양 설계·견적: 소재·가공·규격·부자재를 정하고 수량 구간별 단가로 견적을 드립니다.',
  '디자인 확정·샘플 제작: 실물 샘플로 색상·크기·마감을 확인합니다.',
  '양산: 승인된 샘플을 기준으로 생산하고 QA/QC를 거칩니다.',
  '검품·납품·사후관리: 검품 후 납품하고 추가 생산까지 전담 PM이 맡습니다.',
);
sub contact_aside {   # 견적 CTA
  my ($p, $h2, $text, $subject) = @_;
  return qq(<aside class="contact" aria-label="견적 문의"><h2>$h2</h2><p>$text</p><p class="cta-row"><a class="cta" href="mailto:$EMAIL?subject=@{[ urlenc($subject) ]}">이메일로 문의</a> <a class="cta ghost" href="${p}contact.html#quote">견적 요청서 작성</a> <a class="cta ghost" href="tel:+82-2-930-8000">전화 02-930-8000</a> <a class="cta ghost" href="https://tiska.kr/shopinfo/contact.html" rel="noopener">tiska.kr 문의</a></p></aside>\n);
}
sub case_card {   # $pre: 사례 페이지 기준 경로 접두어(cases/ 안이면 '', 홈이면 'cases/')
  my ($c, $pre, $with_lab, $id) = @_;
  my $g = $G{ $c->{group} };
  my $img = '';
  if (@{ $c->{imgs} }) {
    my $i = $c->{imgs}[0];
    my ($src, $w, $h) = $i->{thumb} ? ("${pre}thumb/$i->{file}", $i->{tw}, $i->{th}) : ("${pre}img/$i->{file}", $i->{w}, $i->{h});
    $img = qq(<img src="$src"@{[ wh($w, $h) ]} alt="@{[ esc("$c->{slabel} 제작 사례") ]}" loading="lazy">);   # 홈 포트폴리오·사례 목록·관련 사례 공통: "{클라이언트} {품목} 제작 사례"(클라이언트 없으면 품목만)
  }
  my $cls = $img ? 'card' : 'card nophoto';
  my $what = $c->{short};
  return qq(<li class="$cls"@{[ $id ? qq( id="$id") : '' ]} data-cat="$c->{group}"><a href="$pre$c->{id}.html">$img<span class="body">)
    . ($with_lab ? qq(<span class="lab">$g->{name}</span>) : '')
    . qq(<b>@{[ esc($c->{client} ne '' ? $c->{client} : $what) ]}</b>) . ($c->{client} ne '' ? qq(<span>@{[ esc($what) ]}</span>) : '')
    . qq(<small>샘플 $g->{s} · 양산 $g->{pd}</small></span></a></li>);
}

# ---------- 머리말 일치 확인(build.pl nav 와 같은지) ----------
{
  my ($h) = slurp('faq.html') =~ m{(<header class="site">.*?</header>)}s;
  die "faq.html: header 없음 — build.pl 을 먼저 실행하세요" unless $h;
  die "머리말 불일치: build.pl 의 nav() 와 site_build.pl 의 nav() 가 다릅니다\n  build.pl: $h\n  site    : " . nav('./', 'faq') . "\n" unless $h eq nav('./', 'faq');
}

# ---------- 2) 사례 상세 ----------
for my $c (@CASES) {
  my $p = '../';
  my $g = $G{ $c->{group} };
  my $isf = $c->{type} eq 'f';
  my @list = @{ $BYG{ $c->{group} } };
  my ($idx) = grep { $list[$_] == $c } 0 .. $#list;
  my $n = scalar @list;
  my @imgs = @{ $c->{imgs} };
  my $first = @imgs ? "${BASE}cases/img/$imgs[0]{file}" : undef;

  # 제작 포인트(템플릿 문장만)
  my @pt;
  my $cl = $c->{client};
  if ($isf) {
    my ($items, $cnt) = ($c->{'제작 품목'} // '', $c->{'품목 수'} // '');
    my $who = $cl ne '' ? "${cl}의 " : '';
    if ($items ne '') {
      my $obj = $cnt ne '' ? "$items($cnt)" : $items;
      push @pt, "$who$c->{name} 공식 MD로 $obj" . josa($cnt ne '' ? $cnt : $items, '을', '를') . ' 함께 제작한 프로젝트 사례입니다.';
    } else {
      push @pt, "$who$c->{name} 공식 MD를 제작한 프로젝트 사례입니다.";
    }
    my $sched = '품목군이 섞여 있어 샘플 1일~2주·양산 7~20일 가운데 가장 오래 걸리는 품목을 기준으로 일정을 잡습니다.';
    # 제작 품목을 쉼표로 나눠 build.pl @ITEMS 정규식(= @GROUPS re, 첫 번째로 맞는 품목군)으로 판정 → 양산·샘플이 가장 긴 품목군
    my @hit = grep { defined } map { my $it = $_; (grep { $it =~ $G{$_}{re} } @GORDER)[0] } grep { $_ ne '' } map { trim($_) } split /,/, $items;
    if (@hit) {
      my %seen; @hit = grep { !$seen{$_}++ } @hit;
      my ($lg) = sort { days($G{$b}{pd}) <=> days($G{$a}{pd}) || days($G{$b}{s}) <=> days($G{$a}{s}) } @hit;   # 정렬은 안정(같으면 품목명 순서)
      $sched .= " 이 프로젝트 기준 샘플 $G{$lg}{s} · 양산 $G{$lg}{pd}(가장 오래 걸리는 $G{$lg}{name} 기준)입니다.";
    }
    push @pt, $sched;
    push @pt, "프로젝트에 들어가는 품목도 각각 $MOQ 제작합니다.";
  } else {
    my ($mat, $plat, $proc, $use) = map { $c->{$_} // '' } ('소재', '도금', '가공', '용도');
    my $subj = ($cl ne '' ? "${cl}의 " : '') . $c->{name} . josa($c->{name}, '은', '는');
    if ($mat ne '' && $proc ne '')    { push @pt, "$subj $mat 소재에 $proc 가공으로 만든 사례입니다."; }
    elsif ($mat ne '')                { push @pt, "$subj $mat 소재로 만든 사례입니다."; }
    elsif ($proc ne '')               { push @pt, "$subj $proc 가공으로 만든 사례입니다."; }
    push @pt, "도금은 ${plat}입니다." if $plat ne '';
    push @pt, "공개된 용도는 ${use}입니다." if $use ne '';
    push @pt, "같은 사양은 $MOQ 제작하며, $g->{name} 기준 샘플 $g->{s}·양산 $g->{pd}" . josa($g->{pd}, '이', '가') . ' 표준입니다. 수량이 늘수록 개당 단가가 내려가고, 단가는 도안 복잡도·가공 방식에 따라 견적 시 수량 구간별로 안내합니다.';
    push @pt, $NADO;
  }

  # 제작 정보 표
  my @rows;
  push @rows, ['클라이언트', $cl] if $cl ne '';
  if ($isf) {
    push @rows, ['프로젝트', $c->{name}];
    push @rows, ['제작 품목', $c->{'제작 품목'}] if ($c->{'제작 품목'} // '') ne '';
    push @rows, ['품목 수', $c->{'품목 수'}] if ($c->{'품목 수'} // '') ne '';
    push @rows, ['최소 수량', $MOQ], ['샘플·양산', '샘플 1일~2주 · 양산 7~20일(품목에 따라)'];
  } else {
    push @rows, ['품목', $c->{name}];
    for my $k ('소재', '도금', '가공', '용도') { push @rows, [$k, $c->{$k}] if ($c->{$k} // '') ne ''; }
    push @rows, ['최소 수량', $MOQ], ['샘플·양산', "$g->{name} 기준 샘플 $g->{s} · 양산 $g->{pd}"];
  }
  push @rows, ['품목군', $g->{name}];

  my $lead = $c->{lead} // '';   # 부제(.lead-sub)로만 쓴다(품목별 사례의 메타 설명 머리에는 쓰지 않음)
  my $desc;
  if ($isf) {
    $desc = cut(($lead ne '' ? ($lead =~ /사례\s*$/ ? "$lead. " : "$lead 사례. ") : "$c->{h1}. ")
      . (($c->{'제작 품목'} // '') ne '' ? "제작 품목 $c->{'제작 품목'}. " : '')
      . "$MOQ, 샘플 1일~2주·양산 7~20일.", 155);
  } else {
    # "{클라이언트} {품목} 제작 사례." + 소재·가공·용도 + "메인 발주 500개부터, 샘플 s·양산 pd." — 155자 안에서 완결된 구절로 끊음
    $desc = fit_phrases(155, "$c->{slabel} 제작 사례.", "$MOQ, 샘플 $g->{s}·양산 $g->{pd}.",
      map { [$_, $c->{$_}] } grep { ($c->{$_} // '') ne '' } '소재', '가공', '용도');
  }

  my $crumbs = crumb_json(['홈', $BASE], ['제작 사례', "${BASE}cases/"], [$g->{name}, "${BASE}cases/#cat-$c->{group}"], [$c->{h1}, $c->{url}]);
  my %work = ('@type' => 'CreativeWork', '@id' => "$c->{url}#work", name => $c->{h1}, description => ($isf ? ($lead ne '' ? $lead : $c->{h1}) : $desc),
    creator => { '@id' => $ORG_ID }, about => { '@type' => 'Thing', name => ($isf && ($c->{'제작 품목'} // '') ne '' ? $c->{'제작 품목'} : $c->{name}) },
    isBasedOn => $c->{tiska}, inLanguage => 'ko-KR');
  $work{image} = [ map { "${BASE}cases/img/$_->{file}" } @imgs ] if @imgs;
  my %page = ('@type' => 'ItemPage', '@id' => $c->{url}, url => $c->{url}, name => $c->{h1}, description => $desc, inLanguage => 'ko-KR', dateModified => $TODAY,
    isPartOf => { '@id' => "${BASE}#website" }, publisher => { '@id' => $ORG_ID }, mainEntity => \%work);
  $page{primaryImageOfPage} = { '@type' => 'ImageObject', url => $first } if $first;
  my $json = graph(\%page, \%ORG, $crumbs);

  my $html = head(p => $p, title => "$c->{h1} | 티스카 굿즈 제작 가이드", desc => $desc, url => $c->{url}, ogtype => 'article', jsonld => $json,
    ($first ? (og => $first, ogsize => [ $imgs[0]{w} || 1080, $imgs[0]{h} || 1080 ]) : ()));
  $html .= nav($p, 'cases') . "\n<main id=\"main\" class=\"wrap\">\n<article>\n";
  $html .= qq(<nav class="crumb" aria-label="현재 위치"><a href="${p}index.html">홈</a> › <a href="./">제작 사례</a> › <a href="./#cat-$c->{group}">$g->{name}</a> › <span>@{[ esc($c->{label}) ]}</span></nav>\n);
  $html .= qq(<h1>@{[ esc($c->{h1}) ]}</h1>\n);
  $html .= qq(<p class="lead-sub">@{[ esc($lead) ]}</p>\n) if $lead ne '';
  $html .= qq(<p class="meta"><time datetime="$TODAY">$ASOF</time> · 주식회사 티스카 · 품목군 $g->{name} · 사진 tiska.kr 공개 사례</p>\n);
  if (@imgs) {
    $html .= qq(<div class="gallery) . (@imgs > 1 ? ' multi' : '') . qq(">);
    my $k = 0;
    for my $i (@imgs) { $k++; my $alt = esc("$c->{label} 제작 사례 사진 $k"); my $ld = $k == 1 ? 'loading="eager" fetchpriority="high"' : 'loading="lazy"'; $html .= qq(<figure><img src="img/$i->{file}"@{[ wh($i->{w}, $i->{h}) ]} alt="$alt" $ld></figure>); }
    $html .= qq(</div>\n<p class="small">사진은 tiska.kr에 공개된 사례 사진입니다. · <a href="$c->{tiska}" rel="noopener">원본 사례 보기(tiska.kr)</a></p>\n);
  } else {
    $html .= qq(<p class="small">이 사례는 공개 사진이 없습니다. · <a href="$c->{tiska}" rel="noopener">원본 사례 보기(tiska.kr)</a></p>\n);
  }
  $html .= qq(<section id="spec"><h2>제작 정보</h2><div class="tbl"><table class="spec"><tbody>)
    . join('', map { qq(<tr><th>$_->[0]</th><td>@{[ esc($_->[1]) ]}</td></tr>) } @rows) . qq(</tbody></table></div></section>\n);
  $html .= qq(<section id="point"><h2>제작 포인트</h2>) . join('', map { '<p>' . esc($_) . '</p>' } @pt) . qq(</section>\n);
  $html .= qq(<section id="howto"><h2>같은 사양으로 만들려면</h2><ol>) . join('', map { "<li>$_</li>" } @STEPS_SHORT) . qq(</ol>)
    . qq(<p>디자인 파일은 AI·PDF·PSD 원본이 가장 좋고, JPG·PNG만 있어도 디자인팀이 도안 작업을 도와 드립니다. 행사일이 정해져 있다면 <a href="../tools/schedule.html">행사일 역산 일정 계산기</a>로 디자인 확정 마감일을 먼저 확인해 보세요.</p></section>\n);
  $html .= qq(<section id="files"><h2>자료 안내</h2><ul><li><strong>원본 파일</strong>: AI·PDF·PSD 원본을 가장 선호합니다.</li><li><strong>이미지만 있을 때</strong>: JPG·PNG도 디자인팀이 도안 작업을 지원합니다.</li><li><strong>디자인 시안</strong>: 무료이며, 디자인과 생산을 함께 진행합니다.</li><li><strong>참고 자료</strong>: 이 사례 페이지 주소와 원하는 느낌의 레퍼런스 이미지를 함께 보내 주시면 사양을 맞추기 쉽습니다.</li></ul></section>\n);
  $html .= contact_aside($p, '이 사례처럼 만들고 싶다면', '이 페이지 주소와 함께 품목, 수량, 희망 납기, 참고 이미지를 보내 주시면 담당 PM이 확인 후 회신합니다. 디자인 시안은 무료입니다.', "[가이드 사례] $c->{label} 제작 문의");

  # 같은 품목군 사례 6개
  my @rel;
  for my $k (1 .. $n - 1) { push @rel, $list[ ($idx + $k) % $n ]; last if @rel >= 6; }
  if (@rel) {
    $html .= qq(<section class="related-cases"><h2>$g->{name} 다른 사례</h2><ul class="cards">) . join('', map { case_card($_, '', 0) } @rel) . qq(</ul><p><a href="./#cat-$c->{group}">$g->{name} 사례 전체 보기 (@{[ $n ]}건)</a></p></section>\n);
  }
  # 관련 링크
  my @links;
  push @links, $isf ? qq(<li><a href="../items/">품목별 최소 수량·기간 10가지</a></li>) : qq(<li><a href="../items/$c->{group}.html">$g->{name} 주문 제작 — 최소 수량·샘플·양산 기간</a></li>);
  my @gp = @{ $GPOSTS{ $c->{group} } };
  if ($isf) { my $ind = $c->{'업종'} // ''; push @gp, 'kpop-concert-md-production' if $ind =~ /엔터/; push @gp, 'golf-gift-moq-and-lead-time' if $ind =~ /골프|스포츠/; }
  push @links, qq(<li><a href="../posts/$_->[0].html">$_->[1]</a></li>) for post_links(@gp, 'sample-to-delivery-6-steps');
  push @links, qq(<li><a href="../posts/$_->[0].html">[이 사례를 다룬 글] $_->[1]</a></li>) for post_links(@{ $CASEPOST{ $c->{id} } // [] });
  push @links, qq(<li><a href="$c->{tiska}" rel="noopener">원본 사례 보기 (tiska.kr)</a></li>);
  $html .= qq(<nav class="related" aria-label="관련 글"><h2>함께 보면 좋은 글</h2><ul>) . join('', @links) . "</ul></nav>\n";
  # 이전/다음
  if ($n > 1) {
    my ($pv, $nx) = ($list[ ($idx - 1) % $n ], $list[ ($idx + 1) % $n ]);
    $html .= qq(<nav class="pager" aria-label="이전·다음 사례"><a class="prev" href="$pv->{id}.html"><span>‹ 이전 사례</span>@{[ esc($pv->{slabel}) ]}</a><a class="next" href="$nx->{id}.html"><span>다음 사례 ›</span>@{[ esc($nx->{slabel}) ]}</a></nav>\n);
  }
  $html .= "</article>\n" . page_end($p);
  spew("cases/$c->{id}.html", $html);
}

# ---------- 1) 사례 포트폴리오 ----------
{
  my $p = '../'; my $url = "${BASE}cases/";
  my $desc = "주식회사 티스카의 굿즈 제작 사례 ${NC}건을 사진 카드로 모았습니다. 품목군 10가지와 프로젝트 MD 세트로 나눠 볼 수 있고, 사례마다 소재·가공·용도와 같은 사양으로 만드는 방법을 정리했습니다. $MOQ.";
  my $i = 0;
  my @items = map { $i++; { '@type' => 'ListItem', position => $i, url => $_->{url}, name => $_->{h1} } } @CASES;
  my $json = graph({ '@type' => 'CollectionPage', '@id' => $url, url => $url, name => "티스카 굿즈 제작 사례(포트폴리오) ${NC}건", description => $desc, inLanguage => 'ko-KR', dateModified => $TODAY,
      publisher => { '@id' => $ORG_ID }, isPartOf => { '@id' => "${BASE}#website" }, mainEntity => { '@type' => 'ItemList', numberOfItems => $NC, itemListElement => \@items } },
    \%ORG, crumb_json(['홈', $BASE], ['제작 사례', $url]));
  my $html = head(p => $p, title => "굿즈 제작 사례(포트폴리오) ${NC}건 | 티스카 굿즈 제작 가이드", desc => $desc, url => $url, ogtype => 'website', jsonld => $json);
  $html .= nav($p, 'cases') . qq(\n<main id="main" class="wrap">\n<nav class="crumb" aria-label="현재 위치"><a href="../index.html">홈</a> › <span>제작 사례</span></nav><h1>티스카 굿즈 제작 사례(포트폴리오)</h1><p class="meta"><time datetime="$TODAY">$ASOF</time> · 주식회사 티스카 · 사진 tiska.kr 공개 사례</p>\n);
  $html .= qq(<section class="answer"><h2>한 줄 요약</h2><p class="lead">공개 사례 ${NC}건(품목별 ${NCP}건, 프로젝트 ${NCF}건)을 사진과 사양으로 정리했습니다. 모든 품목은 $MOQ 제작하며, 사진은 tiska.kr에 공개된 사례 사진입니다.</p></section>\n);
  my @by = (['golf', '골프·스포츠'], ['entertainment', '엔터테인먼트'], ['brand', '기업·브랜드·캐릭터 IP'], ['nonprofit', '비영리·공익']);
  $html .= qq(<p class="links"><strong>분야별 보기</strong> ) . join(' ', map { -f "cases/$_->[0].html" ? qq(<a href="$_->[0].html">$_->[1]</a>) : '' } @by) . qq(</p>\n);
  # 탭: JS 가 있으면 data-cat 필터, 없으면 #cat-{품목군}(그 품목군 첫 카드)으로 이동. 선택 상태는 aria-current.
  $html .= qq(<nav class="tabs" aria-label="품목군 필터"><a href="./" data-tab="all" class="on" aria-current="true">전체 <span>$NC</span></a>);
  for my $t (@TABS) { my $k = scalar @{ $BYG{$t} // [] } or next; $html .= qq(<a href="#cat-$t" data-tab="$t">$G{$t}{name} <span>$k</span></a>); }
  my %first;
  $html .= qq(</nav>\n<p id="tab-count" role="status" aria-live="polite" class="small"></p>\n<ul class="cards" id="case-grid">) . join("\n", map { case_card($_, '', 1, ($first{ $_->{group} }++ ? undef : "cat-$_->{group}")) } @CASES) . qq(</ul>\n);
  $html .= <<'JS';
<script>
(function(){var t=document.querySelectorAll('.tabs a[data-tab]'),c=document.querySelectorAll('#case-grid [data-cat]'),n=document.getElementById('tab-count');
function go(k){var m=0;for(var i=0;i<c.length;i++){var s=k==='all'||c[i].getAttribute('data-cat')===k;c[i].hidden=!s;if(s)m++;}for(var j=0;j<t.length;j++){var on=t[j].getAttribute('data-tab')===k;t[j].className=on?'on':'';if(on){t[j].setAttribute('aria-current','true');}else{t[j].removeAttribute('aria-current');}}if(n)n.textContent='표시 중 '+m+'건';}
for(var j=0;j<t.length;j++){t[j].addEventListener('click',function(e){e.preventDefault();var k=this.getAttribute('data-tab');go(k);try{history.replaceState(null,'',k==='all'?location.pathname:'#cat-'+k);}catch(x){}});}
function tab(h){return /^[a-z-]+$/.test(h)&&document.querySelector('.tabs a[data-tab="'+h+'"]');}
var h=(location.hash||'').replace('#cat-',''),a=tab(h);if(a){go(h);a.parentNode.scrollLeft=a.offsetLeft-a.parentNode.offsetLeft-16;}else{go('all');}
window.addEventListener('hashchange',function(){var h=(location.hash||'').replace('#cat-','');if(tab(h)){go(h);}else if(h===''){go('all');}});})();
</script>
JS
  $html .= qq(<aside class="cta-band" aria-label="견적 문의"><h2>비슷한 굿즈를 만들고 싶다면</h2><p>사례 페이지 주소와 함께 품목, 수량, 희망 납기를 보내 주시면 담당 PM이 확인 후 회신합니다. $MOQ 제작하며 디자인 시안은 무료입니다.</p><p class="cta-row"><a class="cta" href="../contact.html#quote">견적 요청서 작성</a> <a class="cta ghost" href="../guide/">주문 제작 가이드</a> <a class="cta ghost" href="../items/">품목별 최소 수량·기간</a></p></aside>\n);
  $html .= page_end($p);
  spew('cases/index.html', $html);
}

# ---------- 3) 주문 제작 가이드 ----------
my $GUIDE_CHARS;
{
  my $p = '../'; my $url = "${BASE}guide/";
  my $answer = "티스카의 굿즈 주문 제작은 $MOQ 진행하며, 문의 → 시안 → 견적 → 샘플 → 양산 → 납품의 6단계로 이어집니다. 디자인 확정 후 샘플 1일~2주, 승인 샘플 기준 양산 7~20일이 표준이고, 기간은 품목군마다 다릅니다.";
  # 메타 설명·JSON-LD description: 잘라 쓰지 않고 120~160자(공백 포함)의 완결된 문장으로 고정
  my $desc = "티스카 굿즈 주문 제작 가이드. 문의 → 시안 → 견적 → 샘플 → 양산 → 납품 6단계, 시작 전 확인할 4가지, 품목군별 최소 수량($MOQ)과 샘플 1일~2주·양산 7~20일 표준 기간을 정리했습니다.";
  die sprintf("guide/index.html: description %d자(120~160자여야 함)\n", length $desc) if length($desc) < 120 || length($desc) > 160;
  my $k = 0;
  my @hs = map { $k++; { '@type' => 'HowToStep', position => $k, name => $_->[0], text => "$_->[1] 준비할 것: $_->[2]. 소요 기간: $_->[3].", url => "$url#step-$k" } } @STEPS;
  my $json = graph({ '@type' => 'HowTo', '@id' => "$url#howto", url => $url, name => '굿즈 주문 제작 6단계 — 문의부터 납품까지', description => $desc,inLanguage => 'ko-KR', dateModified => $TODAY,
      publisher => { '@id' => $ORG_ID }, isPartOf => { '@id' => "${BASE}#website" }, step => \@hs },
    \%ORG, crumb_json(['홈', $BASE], ['주문 제작 가이드', $url]));
  my $html = head(p => $p, title => '굿즈 주문 제작 가이드 — 문의부터 납품까지 6단계 | 티스카 굿즈 제작 가이드', desc => $desc, url => $url, ogtype => 'article', jsonld => $json);
  my $b = qq(<nav class="crumb" aria-label="현재 위치"><a href="../index.html">홈</a> › <span>주문 제작 가이드</span></nav><h1>굿즈 주문 제작 가이드 — 문의부터 납품까지</h1><p class="meta"><time datetime="$TODAY">$ASOF</time> · 주식회사 티스카</p>\n);
  $b .= qq(<section class="answer"><h2>한 줄 답변</h2><p class="lead">$answer</p></section>\n);
  $b .= qq(<section id="before"><h2>시작 전에 확인할 4가지</h2><ul class="why">)
    . qq(<li><b>① 일정 여유</b><span>샘플·양산 표준 기간에 시안 수정, 검품, 배송 기간의 여유를 더해 행사일에서 거꾸로 계산합니다. 행사일이 정해져 있다면 <a href="../tools/schedule.html">행사일 역산 일정 계산기</a>로 디자인 확정 마감일과 문의 권장일을 먼저 확인해 주세요.</span></li>)
    . qq(<li><b>② 디자인 파일</b><span>로고·캐릭터 파일은 AI·PDF·PSD 원본이 가장 좋습니다. JPG·PNG만 있어도 디자인팀이 도안 작업을 지원합니다. 티스카는 디자인과 생산을 함께 진행하며, 디자인 시안은 무료입니다.</span></li>)
    . qq(<li><b>③ 사용 권한</b><span>캐릭터, 아티스트, 브랜드 로고처럼 권리가 있는 디자인은 사용 권한을 가진 담당자가 의뢰해 주셔야 합니다. 소속사·라이선스 담당 부서의 확인이 필요한 경우 승인 일정도 함께 고려해 주세요.</span></li>)
    . qq(<li><b>④ 승인 샘플 기준 양산</b><span>양산은 승인된 샘플을 기준으로 진행합니다. 승인 뒤에 색상·크기·구성을 바꾸면 샘플을 다시 만들어야 할 수 있어 일정에 영향을 줍니다. 승인 전에 색상, 크기, 로고 위치, 부자재, 포장을 한 번에 정리해 확인해 주세요.</span></li>)
    . qq(</ul></section>\n);
  $b .= qq(<section id="steps"><h2>6단계 상세</h2><p>각 단계에서 티스카가 하는 일과 담당자가 준비할 것을 정리했습니다. 숫자로 안내하는 기간은 샘플과 양산뿐이며, 나머지 단계의 기간은 품목·수량 확정 후 안내합니다.</p><ol class="steps detail">);
  $k = 0;
  for (@STEPS) { $k++; $b .= qq(<li id="step-$k"><b>$_->[0]</b><dl><dt>하는 일</dt><dd>$_->[1]</dd><dt>담당자가 준비할 것</dt><dd>$_->[2]</dd><dt>소요 기간</dt><dd>$_->[3]</dd></dl></li>); }
  $b .= qq(</ol></section>\n);
  $b .= qq(<section id="groups"><h2>품목군별 최소 수량·표준 기간</h2><p>모든 품목군은 $MOQ 제작합니다. 수량이 늘수록 개당 단가가 내려가며, 단가는 도안 복잡도·가공 방식에 따라 견적 단계에서 수량 구간별로 안내합니다. 기간은 디자인 확정 시점부터의 표준 소요 기간입니다.</p><div class="tbl"><table><thead><tr><th>품목군</th><th>최소 수량</th><th>샘플</th><th>양산</th><th>예시</th></tr></thead><tbody>);
  $b .= qq(<tr><td><a href="../items/$_.html">$G{$_}{name}</a></td><td>$MOQ</td><td>$G{$_}{s}</td><td>$G{$_}{pd}</td><td>$G{$_}{ex}</td></tr>) for @GORDER;
  $b .= qq(</tbody></table></div><p class="small">여러 품목을 묶어 진행하는 세트·프로젝트는 가장 오래 걸리는 품목을 기준으로 일정을 잡습니다. 500개 미만의 소량은 자체 소량 제작 쇼핑몰 <a href="https://nadomaker.com">나도메이커(nadomaker.com)</a>에서 제작할 수 있습니다.</p></section>\n);
  $b .= qq(<section id="ask"><h2>문의 때 알려 주시면 좋은 4가지</h2><ol>)
    . qq(<li><strong>품목</strong>: 만들고 싶은 굿즈 종류입니다. 여러 개라면 목록으로 보내 주시고, 비슷한 <a href="../cases/">제작 사례</a> 페이지 주소가 있으면 함께 알려 주세요.</li>)
    . qq(<li><strong>수량과 사이즈</strong>: 품목별 수량과 원하는 크기입니다. 메인 발주는 500개부터이며, 수량 구간을 두세 가지로 알려 주시면 구간별 단가를 비교해 드립니다.</li>)
    . qq(<li><strong>예산과 용도</strong>: 판매용, 증정용·사은품, 행사 배포, 임직원 웰컴키트 등 용도와 대략의 예산 범위입니다. 용도에 맞는 소재와 포장을 제안하는 데 씁니다.</li>)
    . qq(<li><strong>사용 일정</strong>: 행사일, 공연일, 입사일처럼 굿즈가 필요한 날짜입니다. 납품 장소와 분배 방식이 정해져 있다면 함께 알려 주세요.</li>)
    . qq(</ol><p>이 네 가지는 <a href="../contact.html#quote">견적 요청서 작성기</a>에 입력하면 메일로 바로 보낼 수 있는 요청서로 정리됩니다.</p></section>\n);
  my @gl = post_links(qw(sample-to-delivery-6-steps design-file-preparation quote-request-checklist sample-approval-checklist goods-moq-by-item));
  $b .= qq(<nav class="related" aria-label="관련 글"><h2>함께 보면 좋은 글</h2><ul>) . join('', map { qq(<li><a href="../posts/$_->[0].html">$_->[1]</a></li>) } @gl) . qq(<li><a href="../faq.html">자주 묻는 질문</a></li></ul></nav>\n) if @gl;
  $b .= contact_aside($p, '주문 제작 견적 문의', '품목, 수량, 희망 납기, 참고 이미지를 보내 주시면 담당 PM이 확인 후 회신합니다. 디자인 시안은 무료입니다.', '[가이드] 주문 제작 견적 문의');
  $html .= nav($p, 'howto') . qq(\n<main id="main" class="wrap">\n<article>\n$b</article>\n) . page_end($p);
  $GUIDE_CHARS = nospace_len($b);
  spew('guide/index.html', $html);
}

# ---------- 4) 회사 소개 ----------
{
  my $p = './'; my $url = "${BASE}about.html";
  my $desc = '주식회사 티스카는 2022년 설립된 굿즈·프로모션 상품 주문 제작(OEM/ODM) 제조사입니다. 서울 성수동 본사, 중랑구 자체 공장, 중국 광저우·이우 생산 네트워크. 콘서트 MD·팬클럽 키트·웰컴키트·골프 기념품을 디자인부터 납품까지 전담 PM이 진행합니다.';
  my $json = graph({ '@type' => 'AboutPage', '@id' => $url, url => $url, name => '주식회사 티스카 소개', description => $desc, inLanguage => 'ko-KR', dateModified => $TODAY, mainEntity => { '@id' => $ORG_ID } },
    \%ORG_ABOUT, crumb_json(['홈', $BASE], ['회사 소개', $url]));
  my $html = head(p => $p, title => '회사 소개 | 티스카 굿즈 제작 가이드', desc => $desc, url => $url, ogtype => 'website', jsonld => $json);
  my $b = qq(<nav class="crumb" aria-label="현재 위치"><a href="index.html">홈</a> › <span>회사 소개</span></nav>\n<h1>주식회사 티스카(TISKA) 소개</h1>\n<p class="meta">굿즈·프로모션 상품 주문 제작(OEM/ODM) 제조사 · 설립 2022년 3월 1일 · 서울 · <time datetime="$TODAY">$ASOF</time></p>\n);
  $b .= qq(<section class="answer"><h2>한 줄 소개</h2><p class="lead">주식회사 티스카는 재고 상품에 로고를 인쇄하는 업체가 아니라, 도안과 사양을 받아 소재·규격·가공을 새로 설계해 만드는 B2B 주문 제작 제조사입니다. 서울 중랑구 자체 공장과 중국 광저우·이우 생산 네트워크를 함께 운영하고, 메인 발주는 500개부터 진행하며 샘플 1일~2주, 양산 7~20일이 표준입니다. 500개 미만의 소량은 자체 소량 제작 쇼핑몰 나도메이커에서 제작할 수 있습니다.</p></section>\n);
  $b .= qq(<div class="nums" aria-label="핵심 숫자"><div><b>167건</b><span>공개 제작 사례</span></div><div><b>42곳</b><span>고객사</span></div><div><b>2022년 3월</b><span>법인 설립</span></div><div><b>생산 거점</b><span>서울 중랑구 자체 공장 · 중국 광저우·이우</span></div></div>\n);
  $b .= qq(<section id="why"><h2>티스카를 선택하는 이유 6가지</h2><ul class="why">)
    . qq(<li><b>① 디자인과 생산을 한 번에</b><span>내부 디자인팀이 무료 시안을 만들고, 확정된 디자인을 그대로 생산까지 이어 갑니다. JPG·PNG만 있어도 도안 작업을 도와 드립니다.</span></li>)
    . qq(<li><b>② 전담 PM</b><span>첫 문의부터 샘플·양산·납품까지 전담 PM이 일정과 사양을 처음부터 끝까지 챙깁니다.</span></li>)
    . qq(<li><b>③ 승인 샘플 기준 양산과 QA/QC</b><span>실물 샘플을 승인받은 뒤 그 기준으로 양산하고 QA/QC와 검품을 거쳐 납품합니다.</span></li>)
    . qq(<li><b>④ 자체 공장과 해외 생산 네트워크</b><span>서울 중랑구 자체 공장과 중국 광저우·이우 생산 네트워크가 있어, 품목과 일정에 맞춰 국내 생산과 중국 생산 가운데 고를 수 있습니다.</span></li>)
    . qq(<li><b>⑤ 엔터 굿즈 특화 디자인팀과 공개 사례</b><span>엔터테인먼트 굿즈에 특화된 내부 디자인팀이 있고, tiska.kr에 공개된 제작 사례는 167건, 고객사는 42곳입니다.</span></li>)
    . qq(<li><b>⑥ 수출입·해외 운송 지원</b><span>일본·중국·미국·인도네시아 등으로의 수출입 절차와 해외 운송을 지원하며, 자체 브랜드·라이선스 상품을 국내 및 해외 12개국에 유통하고 있습니다.</span></li>)
    . qq(</ul></section>\n);
  $b .= qq(<section id="work"><h2>하는 일</h2><ul>)
    . qq(<li><strong>엔터테인먼트 굿즈</strong>: 콘서트 MD, 팬클럽 키트, 앨범 특전</li>)
    . qq(<li><strong>브랜드 프로모션 상품</strong>: 커스텀 굿즈, 웰컴키트, 사은품(GWP)</li>)
    . qq(<li><strong>프로모션(기획) 상품</strong>: 골프 기념품(볼마커, 헤드커버, 볼타월, 골프공 세트) 등 기획 상품</li>)
    . qq(<li><strong>자체 브랜드·라이선스 상품 유통</strong>: 국내 및 해외 12개국, 일본·중국·미국·인도네시아 수출입 절차·해외 운송 지원</li>)
    . qq(</ul><p>소량·빠른 제작은 자체 소량 제작 쇼핑몰 <a href="https://nadomaker.com">나도메이커(nadomaker.com)</a>에서 운영합니다.</p></section>\n);
  $b .= qq(<section id="process"><h2>진행 순서(6단계)</h2><ol class="steps">) . join('', map { qq(<li><b>$_->[0]</b><span>$_->[1]</span></li>) } @STEPS) . qq(</ol><p><a href="guide/">주문 제작 가이드에서 단계별 준비물 보기</a></p></section>\n);
  $b .= qq(<section id="clients"><h2>제작 실적·고객사(공개분)</h2><p>공개 제작 사례 167건, 고객사 42곳(골프·스포츠 82건, 엔터테인먼트 55건).</p><ul>)
    . qq(<li><strong>골프·스포츠</strong>: 타이틀리스트(Titleist), 팀 타이틀리스트, 풋조이(FootJoy), 몬스터지, 어메이징크리, 스포츠트라이브, 아디다스</li>)
    . qq(<li><strong>엔터테인먼트</strong>: 세븐틴, NCT 127, NCT DREAM, 에스파, 레드벨벳, 방탄소년단(BTS), 슈퍼주니어, 엑소, 아이유, 에이티즈, 하이라이트, 김준수(XIA), 김재중, 폴킴 외</li>)
    . qq(<li><strong>기업·자동차·유통</strong>: 기아자동차, 굿이어타이어, 내셔널지오그래픽</li>)
    . qq(<li><strong>비영리·공익</strong>: 초록우산(ChildFund Korea), 굿네이버스</li>)
    . qq(<li><strong>캐릭터 IP·문화예술·미디어</strong>: 키크니, 멜로우빈, 푸바오, 대림미술관 미스치프, 드라마 「우영우」·「견우와 선녀」·「트웰브」</li>)
    . qq(</ul><p>사례 사진과 사양은 <a href="cases/">제작 사례 포트폴리오 ${NC}건</a>에서 볼 수 있습니다.</p></section>\n);
  $b .= qq(<section id="groups"><h2>품목군별 최소 수량과 표준 기간</h2><div class="tbl"><table><thead><tr><th>품목군</th><th>최소 수량</th><th>샘플</th><th>양산</th><th>예시</th></tr></thead><tbody>);
  $b .= qq(<tr><td><a href="items/$_.html">$G{$_}{name}</a></td><td>$MOQ</td><td>$G{$_}{s}</td><td>$G{$_}{pd}</td><td>$G{$_}{ex}</td></tr>) for @GORDER;
  $b .= qq(</tbody></table></div><p class="note">단가는 도안 복잡도·가공 방식에 따라 견적 단계에서 수량 구간별로 확정됩니다. 주요 가공: 실크 인쇄, 전사·승화전사, UV 인쇄, 자수, 레이저 각인, 도무송 재단, 금형 성형(실리콘·PVC), 아연합금 주조·도금(무광·유광·흑니켈·금장), 에폭시 코팅, 방수 접합, 누빔, 싸바리.</p></section>\n);
  $b .= qq(<section id="info"><h2>회사 정보</h2><div class="tbl"><table><tbody>)
    . qq(<tr><th>상호</th><td>주식회사 티스카 (TISKA)</td></tr>)
    . qq(<tr><th>대표</th><td>오의미</td></tr>)
    . qq(<tr><th>설립일</th><td>2022년 3월 1일</td></tr>)
    . qq(<tr><th>사업자등록번호</th><td>275-88-02236</td></tr>)
    . qq(<tr><th>주소</th><td>본사 서울특별시 성동구 아차산로17길 48, 성수 SKV1센터1 1515호 (성수동2가 280)</td></tr>)
    . qq(<tr><th>생산</th><td>서울 중랑구 자체 공장 · 중국 광저우·이우 생산 네트워크</td></tr>)
    . qq(<tr><th>전화</th><td><a href="tel:+82-2-930-8000">02-930-8000</a></td></tr>)
    . qq(<tr><th>이메일</th><td><a href="mailto:$EMAIL">$EMAIL</a></td></tr>)
    . qq(<tr><th>홈페이지</th><td><a href="https://tiska.kr">https://tiska.kr</a></td></tr>)
    . qq(<tr><th>인스타그램</th><td><a href="https://www.instagram.com/tiska_office" rel="noopener">\@tiska_office</a></td></tr>)
    . qq(<tr><th>네이버 블로그</th><td><a href="https://blog.naver.com/ttiska" rel="noopener">https://blog.naver.com/ttiska</a></td></tr>)
    . qq(<tr><th>나도메이커</th><td><a href="https://nadomaker.com">https://nadomaker.com</a> (자체 소량 제작 쇼핑몰)</td></tr>)
    . qq(</tbody></table></div></section>\n);
  $b .= contact_aside('', '견적·문의', '품목, 수량, 희망 납기, 참고 이미지를 보내 주시면 담당 PM이 확인 후 회신합니다. 디자인 시안은 무료입니다.', '[가이드 회사 소개] 굿즈 제작 견적 문의');
  $html .= nav($p, 'about') . qq(\n<main id="main" class="wrap">\n$b) . page_end($p);
  spew('about.html', $html);
}

# ---------- 5) 문의 + 견적 요청서 작성기 ----------
{
  my $p = './'; my $url = "${BASE}contact.html";
  my $desc = '티스카 굿즈 제작 견적 문의 방법. 품목, 수량, 희망 납기, 참고 이미지를 이메일(ttiska@naver.com)이나 전화(02-930-8000)로 보내 주시면 담당 PM이 확인 후 회신합니다. 견적 요청서 작성기로 내용을 정리해 메일로 보낼 수 있습니다. 메인 발주 500개부터.';
  my $json = graph({ '@type' => 'ContactPage', '@id' => $url, url => $url, name => '티스카 굿즈 제작 견적 문의', description => $desc, inLanguage => 'ko-KR', about => { '@id' => $ORG_ID } }, \%ORG_CONTACT);
  my $html = head(p => $p, title => '굿즈 제작 견적 문의 — 준비할 것과 연락처 | 티스카 굿즈 제작 가이드', desc => $desc, url => $url, ogtype => 'website', jsonld => $json, og => "${BASE}og/faq.png");
  my $b = qq(<nav class="crumb" aria-label="현재 위치"><a href="index.html">홈</a> › <span>견적 문의</span></nav><h1>굿즈 제작 견적 문의</h1><p class="meta"><time datetime="$TODAY">$ASOF</time> · 주식회사 티스카</p>\n);
  $b .= qq(<section class="answer"><h2>한 줄 답변</h2><p class="lead">품목, 수량, 희망 납기, 참고 이미지를 이메일(<a href="mailto:$EMAIL">$EMAIL</a>)이나 전화(<a href="tel:+82-2-930-8000">02-930-8000</a>)로 보내 주시면 담당 PM이 확인 후 회신합니다. 메인 발주는 500개부터이고, 디자인 시안은 무료입니다. 아래 <a href="#quote">견적 요청서 작성기</a>로 내용을 정리해 바로 보낼 수 있습니다.</p></section>\n);
  $b .= qq(<section id="channels"><h2>연락 채널</h2><ul class="cards text">)
    . qq(<li class="card"><span class="body"><b>전화</b><span><a href="tel:+82-2-930-8000">02-930-8000</a></span><small>품목·일정을 통화로 상담</small></span></li>)
    . qq(<li class="card"><span class="body"><b>이메일</b><span><a href="mailto:$EMAIL?subject=@{[ urlenc('[가이드] 굿즈 제작 견적 문의') ]}">$EMAIL</a></span><small>요청서·참고 이미지 첨부</small></span></li>)
    . qq(<li class="card"><span class="body"><b>tiska.kr 문의</b><span><a href="https://tiska.kr/shopinfo/contact.html?from=guide-contact" rel="noopener">문의 페이지</a></span><small>홈페이지 문의 양식</small></span></li>)
    . qq(<li class="card"><span class="body"><b>인스타그램</b><span><a href="https://www.instagram.com/tiska_office" rel="noopener">\@tiska_office</a></span><small>제작 소식</small></span></li>)
    . qq(<li class="card"><span class="body"><b>네이버 블로그</b><span><a href="https://blog.naver.com/ttiska" rel="noopener">blog.naver.com/ttiska</a></span><small>제작 이야기</small></span></li>)
    . qq(</ul></section>\n);
  my $checks = join '', map { qq(<label><input type="checkbox" name="q-item" value="$G{$_}{name}"> $G{$_}{name}</label>) } @GORDER;
  $b .= <<"FORM";
<section id="quote"><h2>견적 요청서 작성기</h2>
<p>아래 칸을 채우고 <strong>요청서 만들기</strong>를 누르면 메일로 보낼 수 있는 요청서가 만들어집니다. 입력한 내용은 이 브라우저 안에만 있고 서버로 전송되지 않습니다. 메인 발주는 500개부터이며, 500개 미만의 소량은 자체 소량 제작 쇼핑몰 <a href="https://nadomaker.com">나도메이커(nadomaker.com)</a>에서 제작할 수 있습니다.</p>
<div class="qf">
<label for="q-company">회사·브랜드</label><input type="text" id="q-company" maxlength="200" autocomplete="organization" placeholder="예: 주식회사 ○○ / 브랜드명">
<div class="row2"><div><label for="q-name">담당자</label><input type="text" id="q-name" maxlength="200" autocomplete="name" placeholder="이름·부서"></div><div><label for="q-email">연락처(이메일)</label><input type="email" id="q-email" maxlength="200" autocomplete="email" placeholder="회신받을 이메일"></div></div>
<fieldset><legend>품목(여러 개 가능)</legend><div class="checks">$checks</div>
<label for="q-item-text">품목 직접 입력</label><input type="text" id="q-item-text" maxlength="200" placeholder="예: 아크릴 키링, 에코백 (쉼표로 구분)"></fieldset>
<div class="row2"><div><label for="q-qty">수량</label><input type="text" id="q-qty" maxlength="200" inputmode="numeric" placeholder="품목별 수량"></div><div><label for="q-date">희망 납기</label><input type="date" id="q-date"></div></div>
<div class="row2"><div><label for="q-use">용도</label><select id="q-use"><option value="">선택해 주세요</option><option>판매용</option><option>증정용·사은품</option><option>행사 배포</option><option>임직원·웰컴키트</option><option>기타</option></select></div>
<div><label for="q-file">디자인 파일</label><select id="q-file"><option value="">선택해 주세요</option><option>AI·PDF·PSD 원본 있음</option><option>JPG·PNG만 있음</option><option>디자인 시안 의뢰</option></select></div></div>
<div class="row2"><div><label for="q-pack">포장</label><select id="q-pack"><option value="">선택해 주세요</option><option>개별 포장</option><option>세트 패키지</option><option>미정</option></select></div>
<div><label for="q-budget">예산 범위(선택)</label><input type="text" id="q-budget" maxlength="200" placeholder="대략의 예산 범위"></div></div>
<label for="q-note">참고 사항</label><textarea id="q-note" rows="4" maxlength="1000" placeholder="사이즈, 색상, 참고 사례 페이지 주소, 납품 장소 등"></textarea>
<p class="cta-row"><button type="button" class="cta" id="q-make">요청서 만들기</button> <button type="button" class="cta ghost" id="q-copy">복사</button> <a class="cta ghost" id="q-mail" href="mailto:$EMAIL?subject=@{[ urlenc('[견적 요청] 굿즈 제작') ]}">메일 앱으로 보내기</a></p>
<p id="q-msg" role="status" aria-live="polite"></p>
<label for="q-out">정리된 요청서</label><textarea id="q-out" rows="12" readonly placeholder="요청서 만들기를 누르면 이곳에 정리됩니다."></textarea>
<p class="hint">참고 사항은 1,000자까지 쓸 수 있습니다. 내용이 길면 메일 앱에는 앞부분만 들어가니 복사 버튼으로 전체를 붙여 넣어 주세요. 메일 앱이 열리지 않으면 복사한 요청서를 $EMAIL 로 보내 주세요. 참고 이미지는 메일에 직접 첨부해 주세요.</p>
</div>
</section>
FORM
  $b .= <<'JS';
<script>
(function(){
var d=document,$=function(i){return d.getElementById(i);};if(!$('q-make'))return;
function v(i){var e=$(i);return e&&e.value?e.value.replace(/^\s+|\s+$/g,''):'';}
function items(){var a=[],c=d.querySelectorAll('#quote input[name="q-item"]');for(var i=0;i<c.length;i++){if(c[i].checked)a.push(c[i].value);}var t=v('q-item-text');if(t)a.push(t);return a;}
function subj(){var s=['[견적 요청]'];if(v('q-company'))s.push(v('q-company'));var it=items();if(it.length)s.push(it.join('·'));if(v('q-qty'))s.push(v('q-qty'));return s.join(' ');}
var FOOT='— 티스카 굿즈 제작 가이드 견적 요청서 작성기에서 정리한 내용입니다.';
function rows(){return [['회사·브랜드',v('q-company')],['담당자',v('q-name')],['연락처(이메일)',v('q-email')],
['품목',items().join(', ')],['수량',v('q-qty')],['희망 납기',v('q-date')],['용도',v('q-use')],
['디자인 파일',v('q-file')],['포장',v('q-pack')],['예산 범위',v('q-budget')],['참고 사항',v('q-note')]];}
function text(only){var L=[subj(),''],R=rows();for(var i=0;i<R.length;i++){if(only&&R[i][1]==='')continue;L.push(R[i][0]+': '+R[i][1]);}L.push('',FOOT);return L.join('\n');}
function make(){var it=items();
$('q-out').value=text(false);
var n=parseInt(v('q-qty').replace(/[^0-9]/g,''),10),m='요청서를 만들었습니다. 복사하거나 메일 앱으로 보내 주세요.';
if(!it.length)m='품목을 하나 이상 골라 주시면 견적이 더 정확해집니다.';
else if(n>0&&n<500)m='메인 발주는 500개부터입니다. 500개 미만이면 나도메이커(nadomaker.com)에서 제작할 수 있습니다.';
var r=mail();if(r.cut)m+=' 내용이 길어 메일 앱에는 앞부분만 넣었습니다. 나머지는 복사해 붙여 주세요(복사 버튼으로 전체 요청서를 복사할 수 있습니다).';
msg(m);$('q-mail').href=r.href;}
function msg(t){$('q-msg').textContent=t;}
function enc(s){try{return encodeURIComponent(s);}catch(e){return encodeURIComponent(s.replace(/[\uD800-\uDFFF]/g,''));}}
function clip(s,n){var lo=0,hi=s.length;while(lo<hi){var k=(lo+hi+1)>>1;if(enc(s.slice(0,k)).length<=n)lo=k;else hi=k-1;}if(lo>0&&/[\uD800-\uDBFF]/.test(s.charAt(lo-1)))lo--;return s.slice(0,lo);}
// 메일 본문: 값이 입력된 항목만 "항목: 값" 한 줄씩(빈 항목 제외). 제목+본문 인코딩 길이 6,000자 상한, 넘으면 앞부분 + 안내.
function mail(){var MAX=6000,TAIL='\n\n(이하 생략 — 나머지는 복사해 붙여 주세요)',s=enc(clip(subj(),120)),b=text(true),cut=false,room=MAX-s.length;
if(enc(b).length>room){cut=true;b=clip(b,room-enc(TAIL).length)+TAIL;}
return {href:'mailto:ttiska'+'@'+'naver.com?subject='+s+'&body='+enc(b),cut:cut};}
$('q-make').addEventListener('click',make);
$('q-mail').addEventListener('click',function(){make();});
$('q-copy').addEventListener('click',function(){if(!$('q-out').value)make();var o=$('q-out'),ok=function(){msg('요청서를 복사했습니다. 메일 본문에 붙여 넣어 주세요.');},
fb=function(){var r=false;try{o.focus();o.select();r=d.execCommand('copy');}catch(e){r=false;}if(r){ok();}else{msg('요청서를 선택해 두었습니다. Ctrl+C(맥은 Cmd+C)로 복사해 주세요.');}};
try{if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(o.value).then(ok,fb);return;}}catch(e){}
fb();});
})();
</script>
JS
  $b .= qq(<section><h2>문의할 때 보내 주시면 좋은 것</h2><div class="tbl"><table><tbody><tr><th>품목</th><td>만들고 싶은 굿즈 종류(여러 개면 목록으로)</td></tr><tr><th>수량</th><td>품목별 수량. 메인 발주는 500개부터, 500개 미만은 <a href="https://nadomaker.com">나도메이커</a></td></tr><tr><th>희망 납기</th><td>행사일·입사일·공연일 등 굿즈가 필요한 날짜 (<a href="tools/schedule.html">일정 계산기</a>로 마감일 확인)</td></tr><tr><th>참고 이미지</th><td>로고·캐릭터 파일(AI·PDF·PSD가 가장 좋고 JPG·PNG도 가능), 원하는 느낌의 레퍼런스</td></tr><tr><th>예산과 용도</th><td>판매용·증정용, 대략의 예산 범위</td></tr></tbody></table></div></section>\n);
  $b .= qq(<section><h2>문의 후 진행 순서</h2><ol><li>담당 PM이 품목·수량·납기를 확인하고 회신합니다.</li><li>디자인팀이 무료 시안을 만듭니다.</li><li>소재·가공·규격을 정하고 수량 구간별 단가로 견적을 드립니다.</li><li>디자인 확정 후 실물 샘플을 만들어 확인합니다(샘플 1일~2주).</li><li>승인된 샘플 기준으로 양산합니다(7~20일).</li><li>검품(QA/QC) 후 납품하고, 이후 사후 관리를 합니다.</li></ol><p><a href="posts/sample-to-delivery-6-steps.html">문의부터 납품까지 6단계 자세히 보기</a> · <a href="guide/">주문 제작 가이드</a></p></section>\n);
  $b .= qq(<aside class="contact" aria-label="연락처"><h2>연락처</h2><p class="cta-row"><a class="cta" href="mailto:$EMAIL?subject=@{[ urlenc('[가이드] 굿즈 제작 견적 문의') ]}">이메일 $EMAIL</a> <a class="cta ghost" href="tel:+82-2-930-8000">전화 02-930-8000</a> <a class="cta ghost" href="https://tiska.kr/shopinfo/contact.html?from=guide-contact" rel="noopener">tiska.kr 문의 페이지</a></p><p><strong>주식회사 티스카(TISKA)</strong> · 본사 서울특별시 성동구 아차산로17길 48, 성수 SKV1센터1 1515호 · 자체 공장 서울 중랑구</p><p class="small">500개 미만 소량은 자체 소량 제작 쇼핑몰 <a href="https://nadomaker.com">나도메이커 nadomaker.com</a></p></aside>\n);
  $html .= nav($p, 'contact') . qq(\n<main id="main" class="wrap">\n$b) . page_end($p);
  spew('contact.html', $html);
}

# ---------- 6) 홈 블록 ----------
{
  my $b = qq(<!-- site:start -->\n);
  $b .= qq(<section id="groups"><h2>제작 품목군 10가지</h2><p class="sec-lead">모든 품목군은 $MOQ 제작합니다. 품목군을 누르면 최소 수량·기간·관련 사례를 볼 수 있습니다.</p><ul class="cards">);
  for my $s (@GORDER) {
    my $g = $G{$s};
    my ($rep) = grep { @{ $_->{imgs} } } @{ $BYG{$s} // [] };
    my $img = '';
    if ($rep) { my $i = $rep->{imgs}[0]; my ($src, $w, $h) = $i->{thumb} ? ("cases/thumb/$i->{file}", $i->{tw}, $i->{th}) : ("cases/img/$i->{file}", $i->{w}, $i->{h}); $img = qq(<img src="$src"@{[ wh($w, $h) ]} alt="@{[ esc("$rep->{label} 제작 사례") ]}" loading="lazy">); }
    my $cnt = scalar @{ $BYG{$s} // [] };
    $b .= qq(<li class="card@{[ $img ? '' : ' nophoto' ]}"><a href="items/$s.html">$img<span class="body"><b>$g->{name}</b><span>$g->{ex}</span><small>$MOQ · 샘플 $g->{s} · 양산 $g->{pd}@{[ $cnt ? " · 사례 ${cnt}건" : '' ]}</small></span></a></li>);
  }
  $b .= qq(</ul></section>\n);
  # 포트폴리오 12장: 품목군을 돌아가며 사진 있는 사례를 고름
  my (@pick, %pos);
  my @pool = grep { scalar grep { @{ $_->{imgs} } } @{ $BYG{$_} // [] } } @TABS;
  while (@pick < 12 && @pool) {
    my @next;
    for my $t (@pool) {
      my @ph = grep { @{ $_->{imgs} } } @{ $BYG{$t} };
      my $k = $pos{$t} // 0; $pos{$t} = $k + 1;
      if ($k < @ph) { push @pick, $ph[$k]; push @next, $t if $k + 1 < @ph; }
      last if @pick >= 12;
    }
    @pool = @next;
  }
  $b .= qq(<section id="portfolio"><h2>제작 사례 포트폴리오</h2><p class="sec-lead">tiska.kr에 공개된 사례 사진입니다. 사례를 누르면 소재·가공·용도와 같은 사양으로 만드는 방법을 볼 수 있습니다.</p><ul class="cards">) . join('', map { case_card($_, 'cases/', 1) } @pick) . qq(</ul><p><a class="cta ghost" href="cases/">사례 전체 보기 ${NC}건</a></p></section>\n);
  $b .= qq(<section id="process"><h2>진행 순서 6단계</h2><ol class="steps">) . join('', map { qq(<li><b>$_->[0]</b><span>$_->[1]</span></li>) } @STEPS) . qq(</ol><p><a href="guide/">주문 제작 가이드에서 단계별 준비물 보기</a></p></section>\n);
  $b .= qq(<section id="why"><h2>티스카를 선택하는 이유</h2><ul class="why">)
    . qq(<li><b>디자인+생산 일괄 · 무료 시안</b><span>내부 디자인팀이 무료 시안을 만들고 확정된 디자인을 그대로 생산까지 이어 갑니다.</span></li>)
    . qq(<li><b>전담 PM</b><span>첫 문의부터 납품·사후관리까지 전담 PM이 일정과 사양을 챙깁니다.</span></li>)
    . qq(<li><b>승인 샘플 기준 양산 · QA/QC</b><span>실물 샘플을 승인받은 뒤 그 기준으로 양산하고 검품합니다.</span></li>)
    . qq(<li><b>자체 공장 + 광저우·이우</b><span>서울 중랑구 자체 공장과 중국 광저우·이우 생산 네트워크에서 국내·중국 생산을 고를 수 있습니다.</span></li>)
    . qq(</ul><p><a href="about.html">회사 소개 자세히 보기</a></p></section>\n);
  $b .= qq(<aside class="cta-band" aria-label="견적 문의"><h2>굿즈 제작, 견적부터 받아 보세요</h2><p>품목, 수량, 희망 납기를 알려 주시면 담당 PM이 확인 후 회신합니다. $MOQ 제작하며 디자인 시안은 무료입니다.</p><p class="cta-row"><a class="cta" href="contact.html#quote">견적 문의</a> <a class="cta ghost" href="guide/">주문 제작 가이드</a></p></aside>\n);
  $b .= qq(<!-- site:end -->);
  my $s = slurp('index.html');
  # 위치: <!-- quick:end --> 가 들어 있는 hero 섹션의 </section> 바로 뒤(hero 안에 넣지 않음). 이미 있으면 지우고 다시 넣는다(멱등).
  $s =~ s{\n?<!-- site:start -->.*?<!-- site:end -->\n?}{\n}s;
  my $q = index($s, '<!-- quick:end -->');
  die 'index.html: <!-- quick:end --> 표식 없음 — build.pl 을 먼저 실행하세요' if $q < 0;
  my $e = index($s, "</section>\n", $q);
  die 'index.html: quick:end 뒤에 hero 를 닫는 </section> 없음' if $e < 0;
  $e += length "</section>\n";
  substr($s, $e, 0) = "$b\n";
  spew('index.html', $s);
}

# ---------- 7) sitemap.xml ----------
{
  my $sm = slurp('sitemap.xml');
  my @locs = ('guide/', map { "cases/$_->{id}.html" } @CASES);
  for my $l (@locs) { my $q = quotemeta("$BASE$l"); $sm =~ s{<url><loc>$q</loc>.*?</url>\n?}{}gs; }
  my $add = join '', map { qq(<url><loc>$BASE$_</loc><lastmod>$TODAY</lastmod><changefreq>monthly</changefreq></url>\n) } @locs;
  $sm =~ s{</urlset>}{$add</urlset>} or die 'sitemap.xml: </urlset> 없음';
  spew('sitemap.xml', $sm);
  my $total = () = $sm =~ /<url>/g;
  print "sitemap: +", scalar(@locs), " URLs (합계 $total)\n";
}

# ---------- 8) llms.txt ----------
{
  my %cnt = map { $_ => scalar @{ $BYG{$_} // [] } } @TABS;
  my $sec = "<!-- site:llms:start -->\n## 주문 제작 가이드·포트폴리오\n"
    . "- [주문 제작 가이드](${BASE}guide/): $MOQ, 문의→시안→견적→샘플→양산→납품 6단계, 디자인 확정 후 샘플 1일~2주·승인 샘플 기준 양산 7~20일. 시작 전에 확인할 4가지(일정 여유, 디자인 파일, 사용 권한, 승인 샘플 기준 양산)와 단계별 준비물, 품목군별 표준 기간.\n"
    . "- [제작 사례 포트폴리오 ${NC}건](${BASE}cases/): tiska.kr 공개 사례 ${NC}건(품목별 ${NCP}건, 프로젝트 ${NCF}건)을 사진·제작 정보(소재·도금·가공·용도)와 품목군별로 정리. 사례마다 상세 페이지(예: ${BASE}cases/$CASES[0]{id}.html). 품목군별 건수: " . join(', ', map { "$G{$_}{name} $cnt{$_}건" } grep { $cnt{$_} } @TABS) . ".\n"
    . "- [회사 소개](${BASE}about.html): 공개 제작 사례 167건, 고객사 42곳, 법인 설립 2022년 3월, 생산 거점(서울 중랑구 자체 공장·중국 광저우·이우), 티스카를 선택하는 이유 6가지, 회사 정보.\n"
    . "- [견적 요청서 작성기](${BASE}contact.html#quote): 회사·품목·수량·희망 납기·용도·디자인 파일·포장을 입력하면 메일로 보낼 요청서를 만들어 줍니다(입력 내용은 브라우저 안에만 있음). 이메일 $EMAIL · 전화 02-930-8000.\n"
    . "<!-- site:llms:end -->";
  my $s = slurp('llms.txt');
  if ($s =~ /<!-- site:llms:start -->/) { $s =~ s{<!-- site:llms:start -->.*?<!-- site:llms:end -->}{$sec}s; }
  else { $s =~ s/\s*$//; $s .= "\n\n$sec\n"; }
  spew('llms.txt', $s);
}

# ---------- 점검(경고만) ----------
{
  my @files = ('cases/index.html', (map { "cases/$_->{id}.html" } @CASES), 'guide/index.html', 'about.html', 'contact.html', 'index.html');
  my $bad = qr/판촉물|500개 단위|500개씩|받지 않|불가|대응이 어렵|인력 부족|최저가|업계 1위|국내 유일|최고|보장/;
  my $old = qr/(?<![0-9~,])(?:10|50|100|300)개부터/;
  my $warn = 0;
  my @hard;
  for my $f (@files) {
    my $t = slurp($f);
    if ($f eq 'index.html') { ($t) = $t =~ /(<!-- site:start -->.*?<!-- site:end -->)/s; $t //= ''; }
    push @hard, $f if $t =~ /판촉/;   # 제목·메타·JSON-LD·alt 포함 원문 전체에서 검사(norm_word 로 치환되므로 나오면 생성기 문구 오류)
    $t =~ s{<script.*?</script>}{}gs; $t =~ s/<[^>]+>/ /g;
    if ($t =~ /($bad)/) { print "WARN $f: 금지어 '$1'\n"; $warn++; }
    if ($t =~ /($old)/) { print "WARN $f: 옛 최소 수량 '$1'\n"; $warn++; }
  }
  die "금지어 '판촉'이 site_build 출력에 있습니다: @hard\n" if @hard;
  # build.pl 이 만든 다른 페이지(분야별 사례·품목)는 경고만
  for my $f (grep { !/\/[pf]\d+\.html$/ && $_ ne 'cases/index.html' } glob('cases/*.html'), glob('items/*.html')) {
    if (slurp($f) =~ /판촉/) { print "WARN $f: 금지어 '판촉'(build.pl 입력 _build/cases.tsv 확인)\n"; $warn++; }
  }
  print "WARN guide/index.html: 분량 ${GUIDE_CHARS}자(<1200)\n" if $GUIDE_CHARS < 1200;
  print "점검: 경고 ${warn}건\n";
}
printf "site_build 완료(%s): 사례 상세 %d개(품목별 %d · 프로젝트 %d), 건너뛴 행 %d개(%s), 품목군 %d개 + 프로젝트 MD 세트, 주문 제작 가이드 %d자\n",
  $ASOF, $NC, $NCP, $NCF, scalar(@SKIPPED), join(',', @SKIPPED), scalar(@GORDER), $GUIDE_CHARS;
printf "  %s %d건\n", $G{$_}{name}, scalar @{ $BYG{$_} // [] } for @TABS;
