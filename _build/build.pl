#!/usr/bin/perl
# 티스카 굿즈 제작 가이드 — Q&A 페이지 생성기
# 사용법(Git Bash, 저장소 루트에서):  perl _build/build.pl
# 하는 일:
#   1) _build/qa.txt → qa/{번호}/index.html (질문 1개 = 페이지 1개, FAQPage 구조화 데이터)
#   2) faq.html → 분류별 질문 목록(ItemList)으로 다시 생성
#   3) posts/*.html → "이 주제의 자주 묻는 질문" 링크 블록 삽입/갱신
#   4) 모든 페이지 상단 메뉴에 "일정 계산기" 추가(이미 있으면 그대로)
#   5) sitemap.xml 다시 생성, llms.txt·llms-full.txt의 Q&A 구역 갱신
# 도메인을 옮기면 아래 $BASE 한 줄만 바꾸고 다시 실행하세요.
# (_ 로 시작하는 폴더는 GitHub Pages(Jekyll)가 공개하지 않습니다.)
use strict;
use warnings;
use utf8;
use open qw(:std :encoding(UTF-8));
use Encode qw(encode_utf8);
use File::Path qw(make_path);
use File::Basename qw(dirname);

my $BASE  = 'https://ohyoumeee-prog.github.io/tiska-guide/';
my $TODAY = '2026-11-11';
my $TODAY_KO = '2026년 11월 11일';

my $ROOT = dirname(dirname(__FILE__));
chdir $ROOT or die "cannot chdir $ROOT";

my %CAT = (
  moq     => '수량·소량',
  time    => '기간·일정',
  cost    => '비용·견적',
  design  => '디자인·파일',
  sample  => '샘플·품질',
  prod    => '생산·가공',
  ent     => '콘서트·엔터 MD',
  golf    => '골프 굿즈',
  kit     => '웰컴키트·기업 선물',
  npo     => '비영리·캠페인',
  oem     => '자체 브랜드·OEM/ODM',
  company => '회사·진행 방식',
);
my @CAT_ORDER = qw(moq time cost design sample prod ent golf kit npo oem company);

my %CAT_TISKA = (
  ent  => ['엔터테인먼트 굿즈 제작 안내 (tiska.kr)', 'https://tiska.kr/shopinfo/goods_entertainment.html'],
  golf => ['골프 대회 기념품·골프 굿즈 제작 안내 (tiska.kr)', 'https://tiska.kr/shopinfo/goods_golf.html'],
  kit  => ['임직원 웰컴키트·기업 선물 세트 제작 안내 (tiska.kr)', 'https://tiska.kr/shopinfo/goods_welcomekit.html'],
  npo  => ['비영리 단체·캠페인 굿즈 제작 안내 (tiska.kr)', 'https://tiska.kr/shopinfo/goods_nonprofit.html'],
);
my @ALL_CASES = (
  ['품목별 제작 사례 138건 (tiska.kr 제작사례)', 'https://tiska.kr/board/magazine/list.html?board_no=5'],
  ['프로젝트 제작 사례 29건 (tiska.kr 포트폴리오)', 'https://tiska.kr/board/gallery/list.html?board_no=8'],
);

# ---------- 유틸 ----------
sub slurp { my $f = shift; open my $h, '<', $f or die "read $f: $!"; local $/; my $s = <$h>; close $h; $s =~ s/\r\n/\n/g; return $s; }
sub spew  { my ($f, $s) = @_; make_path(dirname($f)); open my $h, '>', $f or die "write $f: $!"; print $h $s; close $h; }
sub esc   { my $s = shift // ''; $s =~ s/&(?![a-zA-Z#0-9]+;)/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; return $s; }
sub plain {
  my $s = shift // '';
  $s =~ s{</t[hd]>\s*}{ / }g; $s =~ s{</tr>}{; }g; $s =~ s{<li>}{· }g; $s =~ s{</(p|li|ul|div)>}{ }g;
  $s =~ s/<[^>]+>//g; $s =~ s/&nbsp;/ /g; $s =~ s/&amp;/&/g; $s =~ s/&lt;/</g; $s =~ s/&gt;/>/g; $s =~ s/&quot;/"/g;
  $s =~ s/ \/ ;/;/g; $s =~ s/\s+/ /g; $s =~ s/^\s+|\s+$//g; return $s;
}
sub jstr  { my $s = shift // ''; $s =~ s/\\/\\\\/g; $s =~ s/"/\\"/g; $s =~ s/\n/ /g; $s =~ s{</}{<\\/}g; return qq("$s"); }
sub urlenc { my $b = encode_utf8(shift); $b =~ s/([^A-Za-z0-9\-_.~])/sprintf('%%%02X', ord $1)/ge; return $b; }
sub cut   { my ($s, $n) = @_; return $s if length($s) <= $n; $s = substr($s, 0, $n); $s =~ s/\s+\S*$//; return "$s…"; }
sub case_url {
  my $c = shift;
  return "https://tiska.kr/article/product/5/$1/"   if $c =~ /^P:(\d+)$/;
  return "https://tiska.kr/article/portfolio/8/$1/" if $c =~ /^F:(\d+)$/;
  die "bad case ref $c";
}

# ---------- 데이터 읽기 ----------
my (@qa, %byid, $cur, $inmore);
for my $line (split /\n/, slurp('_build/qa.txt')) {
  next if !$cur && ($line =~ /^#/ || $line =~ /^\s*$/);
  if ($line =~ /^=== (\d+)\s*$/) { $cur = { id => $1, more => '' }; push @qa, $cur; $inmore = 0; next; }
  next unless $cur;
  if ($line =~ /^(cat|q|a|guides|cases):\s*(.*)$/) { $cur->{$1} = $2; $inmore = 0; next; }
  if ($line =~ /^more:\s*$/) { $inmore = 1; next; }
  if ($inmore) { $cur->{more} .= "$line\n"; next; }
  die "Q$cur->{id}: 알 수 없는 줄: $line" if $line =~ /\S/;
}
for my $q (@qa) {
  for (qw(cat q a)) { die "Q$q->{id}: '$_' 없음" unless defined $q->{$_} && length $q->{$_}; }
  die "Q$q->{id}: 분류 '$q->{cat}' 없음" unless $CAT{$q->{cat}};
  die "Q$q->{id}: 번호 중복" if $byid{$q->{id}}++;
  $q->{more} =~ s/\s+$//;
  $q->{guides} = [ grep { length } map { s/^\s+|\s+$//gr } split /,/, ($q->{guides} // '') ];
  $q->{cases}  = [ map { my ($r, $n) = split /\|/, $_, 2; [ ($n // '') =~ s/^\s+|\s+$//gr, case_url($r =~ s/^\s+|\s+$//gr) ] }
                   grep { /\S/ } split /,/, ($q->{cases} // '') ];
  $q->{url}   = "${BASE}qa/$q->{id}/";
  $q->{plain} = plain($q->{a} . ' ' . $q->{more});
  $q->{desc}  = cut(plain($q->{a}), 150);
}
my $N = scalar @qa;

# 가이드 글 제목
my %GUIDE;
for my $f (glob 'posts/*.html') {
  my ($slug) = $f =~ m{posts/(.+)\.html$};
  my ($h1) = slurp($f) =~ m{<h1>(.*?)</h1>}s;
  $GUIDE{$slug} = $h1 // $slug;
}
for my $q (@qa) { for (@{ $q->{guides} }) { die "Q$q->{id}: 가이드 '$_' 없음" unless $GUIDE{$_}; } }

# ---------- 공통 조각 ----------
sub nav {
  my ($p, $cur) = @_;
  my @items = (['index.html', '가이드', 'guide'], ['items/', '품목', 'items'], ['cases/', '제작 사례', 'cases'], ['faq.html', '자주 묻는 질문', 'faq'], ['tools/schedule.html', '일정 계산기', 'tool'], ['about.html', '회사 소개', 'about'], ['contact.html', '문의', 'contact']);
  my $s = qq(<header class="site"><div class="wrap"><a class="brand" href="${p}index.html">티스카 <span>굿즈 제작 가이드</span></a><nav aria-label="주 메뉴">);
  for (@items) { $s .= qq(<a href="$p$_->[0]") . ($cur eq $_->[2] ? ' aria-current="page"' : '') . qq(>$_->[1]</a>); }
  return $s . qq(<a href="https://tiska.kr" rel="noopener">tiska.kr</a></nav></div></header>);
}
sub footer {
  my $p = shift;
  return qq(<footer class="site"><div class="wrap"><p><strong>주식회사 티스카</strong> · 굿즈·프로모션 상품 주문 제작(OEM/ODM) · 사업자등록번호 275-88-02236 · 대표 오의미</p><p>본사 서울특별시 성동구 아차산로17길 48, 성수 SKV1센터1 1515호 · 자체 공장 서울 중랑구 · 생산 네트워크 중국 광저우·이우</p><p>전화 <a href="tel:+82-2-930-8000">02-930-8000</a> · 이메일 <a href="mailto:ttiska\@naver.com">ttiska\@naver.com</a> · <a href="https://tiska.kr">tiska.kr</a> · 소량·빠른 제작 <a href="https://nadomaker.com">nadomaker.com</a> · <a href="https://www.instagram.com/tiska_office" rel="noopener">Instagram</a> · <a href="https://blog.naver.com/ttiska" rel="noopener">네이버 블로그</a></p><p>모든 숫자는 tiska.kr 공개 정보 기준($TODAY_KO). · <a href="${p}llms.txt">llms.txt</a> · <a href="${p}rss.xml">RSS</a> · <a href="${p}sitemap.xml">사이트맵</a> · © 2026 주식회사 티스카</p></div></footer>);
}
my $ORG_JSON = qq({"\@type":"Organization","\@id":"https://tiska.kr/#organization","name":"주식회사 티스카","alternateName":["TISKA","티스카"],"url":"https://tiska.kr","logo":{"\@type":"ImageObject","url":"${BASE}logo.png","width":512,"height":512}});
sub head {
  my (%o) = @_;
  my $p = $o{p};
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
<meta property="og:image" content="${BASE}og/faq.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
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

# ---------- 1) 질문별 페이지 ----------
for my $q (@qa) {
  my $p = '../../';
  my $catname = $CAT{$q->{cat}};
  my $title = "$q->{q} | 티스카 굿즈 제작 Q&A";
  my $faqjson = qq({"\@type":"FAQPage","\@id":) . jstr("$q->{url}#faq") . qq(,"url":) . jstr($q->{url})
    . qq(,"name":) . jstr($q->{q}) . qq(,"inLanguage":"ko-KR","datePublished":"$TODAY","dateModified":"$TODAY")
    . qq(,"isPartOf":{"\@id":"${BASE}#website"},"publisher":{"\@id":"https://tiska.kr/#organization"},"about":) . jstr($catname)
    . qq(,"mainEntity":[{"\@type":"Question","name":) . jstr($q->{q})
    . qq(,"acceptedAnswer":{"\@type":"Answer","text":) . jstr($q->{plain}) . qq(,"url":) . jstr($q->{url}) . qq(,"author":{"\@id":"https://tiska.kr/#organization"}}}]});
  my $crumb = qq({"\@type":"BreadcrumbList","itemListElement":[{"\@type":"ListItem","position":1,"name":"홈","item":"$BASE"},{"\@type":"ListItem","position":2,"name":"자주 묻는 질문","item":"${BASE}faq.html"},{"\@type":"ListItem","position":3,"name":) . jstr($catname) . qq(,"item":"${BASE}faq.html#$q->{cat}"},{"\@type":"ListItem","position":4,"name":) . jstr("Q$q->{id}") . qq(,"item":) . jstr($q->{url}) . qq(}]});
  my $json = qq({"\@context":"https://schema.org","\@graph":[$faqjson,$ORG_JSON,$crumb]});

  my $html = head(p => $p, title => $title, desc => $q->{desc}, url => $q->{url}, ogtype => 'article', jsonld => $json);
  $html .= nav($p, 'faq') . "\n<main id=\"main\" class=\"wrap\">\n<article>\n";
  $html .= qq(<nav class="crumb" aria-label="현재 위치"><a href="${p}index.html">홈</a> › <a href="${p}faq.html">자주 묻는 질문</a> › <a href="${p}faq.html#$q->{cat}">$catname</a> › <span>Q$q->{id}</span></nav>\n);
  $html .= qq(<h1>@{[ esc($q->{q}) ]}</h1>\n<p class="meta"><time datetime="$TODAY">$TODAY_KO</time> · 답변 주식회사 티스카 · 분류 $catname</p>\n);
  $html .= qq(<section id="answer" class="answer">\n<h2>짧은 답</h2>\n<p class="lead">$q->{a}</p>\n</section>\n);
  if ($q->{more} ne '') {
    my $more = $q->{more}; $more = "<p>$more</p>" unless $more =~ /^\s*</;
    $html .= qq(<section id="detail">\n<h2>자세히</h2>\n$more\n</section>\n);
  }
  # 견적 문의
  my $subj = urlenc("[가이드 Q$q->{id}] $q->{q}");
  $html .= qq(<aside class="contact" aria-label="문의"><h2>이 내용으로 견적 문의하기</h2><p>품목, 수량, 희망 납기, 참고 이미지를 보내 주시면 담당 PM이 확인 후 회신합니다.</p><p class="cta-row"><a class="cta" href="mailto:ttiska\@naver.com?subject=$subj">이메일로 문의</a> <a class="cta ghost" href="https://tiska.kr/shopinfo/contact.html?from=guide-qa-$q->{id}" rel="noopener">tiska.kr 문의 페이지</a> <a class="cta ghost" href="tel:+82-2-930-8000">전화 02-930-8000</a></p><p class="small">500개 미만 소량은 <a href="https://nadomaker.com">나도메이커 nadomaker.com</a></p></aside>\n);
  # 근거 가이드
  if (@{ $q->{guides} }) {
    $html .= qq(<nav class="related" aria-label="근거 가이드"><h2>근거가 되는 가이드 글</h2><ul>);
    $html .= qq(<li><a href="${p}posts/$_.html">$GUIDE{$_}</a></li>) for @{ $q->{guides} };
    $html .= "</ul></nav>\n";
  }
  # tiska.kr 사례
  my @links = (@{ $q->{cases} }, ($CAT_TISKA{$q->{cat}} ? ($CAT_TISKA{$q->{cat}}) : ()), @ALL_CASES);
  $html .= qq(<nav class="related cases" aria-label="제작 사례"><h2>tiska.kr 제작 사례</h2><ul>);
  $html .= qq(<li><a href="$_->[1]" rel="noopener">@{[ esc($_->[0]) ]}</a></li>) for @links;
  $html .= "</ul></nav>\n";
  # 같은 분류의 다른 질문
  my @same = grep { $_->{cat} eq $q->{cat} && $_->{id} != $q->{id} } @qa;
  if (@same) {
    $html .= qq(<nav class="related" aria-label="같은 분류의 질문"><h2>$catname — 다른 질문</h2><ul>);
    $html .= qq(<li><a href="${p}qa/$_->{id}/">@{[ esc($_->{q}) ]}</a></li>) for @same[0 .. ($#same < 5 ? $#same : 5)];
    $html .= "</ul></nav>\n";
  }
  $html .= qq(<p class="md-link">이 답의 숫자는 tiska.kr 공개 정보와 가이드 글 기준($TODAY_KO)입니다. 정확한 단가·조건은 견적 시 확정됩니다. 전체 질문은 <a href="${p}faq.html">자주 묻는 질문 ${N}개</a>, AI 도구용 원문은 <a href="${p}llms-full.txt">llms-full.txt</a>에 있습니다.</p>\n);
  $html .= "</article>\n</main>\n" . footer($p) . "\n</body>\n</html>\n";
  spew("qa/$q->{id}/index.html", $html);
}

# ---------- 2) faq.html (목록) ----------
{
  my $p = './';
  my $url = "${BASE}faq.html";
  my $desc = "굿즈·MD 주문 제작에 대해 담당자들이 자주 묻는 질문 ${N}개. 최소 수량, 샘플·양산 기간, 비용·견적, 디자인 파일, 국내·중국 생산, 콘서트 MD, 골프 기념품, 웰컴키트, 비영리 굿즈를 질문별 페이지로 답합니다.";
  my $items = join ',', map { qq({"\@type":"ListItem","position":) . ($_ + 1) . qq(,"url":) . jstr($qa[$_]{url}) . qq(,"name":) . jstr($qa[$_]{q}) . '}' } 0 .. $#qa;
  my $json = qq({"\@context":"https://schema.org","\@graph":[{"\@type":"CollectionPage","\@id":"$url","url":"$url","name":"굿즈 제작 자주 묻는 질문 ${N}개","description":) . jstr($desc)
    . qq(,"inLanguage":"ko-KR","dateModified":"$TODAY","publisher":{"\@id":"https://tiska.kr/#organization"},"isPartOf":{"\@id":"${BASE}#website"},"mainEntity":{"\@type":"ItemList","numberOfItems":$N,"itemListElement":[$items]}},$ORG_JSON,{"\@type":"BreadcrumbList","itemListElement":[{"\@type":"ListItem","position":1,"name":"홈","item":"$BASE"},{"\@type":"ListItem","position":2,"name":"자주 묻는 질문","item":"$url"}]}]});
  my $html = head(p => $p, title => "굿즈 제작 자주 묻는 질문 ${N}개 | 티스카 굿즈 제작 가이드", desc => $desc, url => $url, ogtype => 'website', jsonld => $json);
  $html .= nav($p, 'faq') . "\n<main id=\"main\" class=\"wrap\">\n";
  $html .= qq(<nav class="crumb" aria-label="현재 위치"><a href="index.html">홈</a> › <span>자주 묻는 질문</span></nav><h1>굿즈 제작, 자주 묻는 질문 ${N}개</h1><p class="meta"><time datetime="$TODAY">$TODAY_KO</time> · 주식회사 티스카</p>);
  $html .= qq(<p>질문을 누르면 질문별 페이지에서 근거 표, 관련 가이드, tiska.kr 제작 사례를 함께 볼 수 있습니다. 숫자는 tiska.kr 공개 정보 기준입니다. 행사일이 정해져 있다면 <a href="tools/schedule.html">행사일 역산 일정 계산기</a>를 먼저 써 보세요.</p>\n);
  $html .= qq(<nav class="chips" aria-label="분류">) . join('', map { my $c = $_; my $n = grep { $_->{cat} eq $c } @qa; $n ? qq(<a href="#$c">$CAT{$c} <span>$n</span></a>) : '' } @CAT_ORDER) . "</nav>\n";
  for my $c (@CAT_ORDER) {
    my @list = grep { $_->{cat} eq $c } @qa or next;
    $html .= qq(<section id="$c"><h2>$CAT{$c}</h2>);
    for my $q (@list) {
      $html .= qq(<div class="faq-item"><h3><a href="qa/$q->{id}/">@{[ esc($q->{q}) ]}</a></h3><p>$q->{a}</p></div>);
    }
    $html .= "</section>\n";
  }
  $html .= qq(<aside class="contact" aria-label="문의"><h2>견적·문의</h2><p><strong>주식회사 티스카(TISKA)</strong> · 본사 서울 성동구 성수동 · 자체 공장 서울 중랑구</p><p>전화 <a href="tel:+82-2-930-8000">02-930-8000</a> · 이메일 <a href="mailto:ttiska\@naver.com">ttiska\@naver.com</a> · 홈페이지 <a href="https://tiska.kr/shopinfo/contact.html?from=guide-faq">tiska.kr</a></p><p>소량·빠른 제작은 <a href="https://nadomaker.com">나도메이커 nadomaker.com</a></p></aside>\n);
  $html .= "</main>\n" . footer($p) . "\n</body>\n</html>\n";
  spew('faq.html', $html);
}

# ---------- 3) 가이드 글에 관련 질문 링크 ----------
for my $f (glob 'posts/*.html') {
  my ($slug) = $f =~ m{posts/(.+)\.html$};
  my @rel = grep { my $q = $_; grep { $_ eq $slug } @{ $q->{guides} } } @qa;
  my $s = slurp($f);
  my $block = '';
  if (@rel) {
    @rel = @rel[0 .. ($#rel < 7 ? $#rel : 7)];
    $block = qq(<!-- qa-links:start -->\n<nav class="related" aria-label="이 주제의 질문"><h2>이 주제의 자주 묻는 질문</h2><ul>)
      . join('', map { qq(<li><a href="../qa/$_->{id}/">@{[ esc($_->{q}) ]}</a></li>) } @rel)
      . qq(</ul></nav>\n<!-- qa-links:end -->\n);
  }
  if ($s =~ /<!-- qa-links:start -->/) { $s =~ s{<!-- qa-links:start -->.*?<!-- qa-links:end -->\n?}{$block}s; }
  else { $s =~ s{(<p class="md-link">)}{$block$1} or die "$f: md-link 위치 없음"; }
  spew($f, $s);
}

# ---------- 4) 메뉴(손으로 쓴 페이지) ----------
for my $f ('index.html', 'about.html', '404.html', 'tools/schedule.html', glob('posts/*.html')) {
  my $s = slurp($f);
  my $p = $f =~ m{/} ? '../' : './';
  my $cur = $f eq 'index.html' || $f =~ m{^posts/} ? 'guide' : $f eq 'about.html' ? 'about' : $f =~ /schedule/ ? 'tool' : '';
  $s =~ s{<header class="site">.*?</header>}{nav($p, $cur)}se or die "$f: 메뉴 위치 없음";
  spew($f, $s);
}

# ---------- 4-1) 제작 사례 데이터 ----------
my @CASES;
{
  my @lines = split /\n/, slurp('_build/cases.tsv');
  my @h = split /\t/, shift @lines;
  for (@lines) { my @v = split /\t/, $_, -1; my %r; @r{@h} = @v; push @CASES, \%r; }
}
my @CASE_GROUPS = (
  ['golf', '골프·스포츠', qr/골프|스포츠/, '골프 브랜드·골프 대회·스포츠 단체를 위해 만든 사례입니다. 볼마커, 디봇툴, 헤드커버, 네임택, 볼타월, 파우치, 트로피 패키지 등이 있습니다.', 'posts/golf-gift-moq-and-lead-time.html', 'https://tiska.kr/shopinfo/goods_golf.html'],
  ['entertainment', '엔터테인먼트', qr/엔터/, '콘서트 MD, 팬클럽 키트, 팬미팅·전시 MD를 만든 사례입니다. 아크릴 키링, 응원부채, 금속 뱃지, 팔찌, 봉제 인형, 포토카드 패키지 등이 있습니다.', 'posts/kpop-concert-md-production.html', 'https://tiska.kr/shopinfo/goods_entertainment.html'],
  ['brand', '기업·브랜드·캐릭터 IP', qr/제조|자동차|라이프|개인|캐릭터|문화|미디어/, '기업 프로모션 제품, 연말 기프트 패키지, 캐릭터 IP 상품, 드라마·전시 굿즈를 만든 사례입니다.', 'posts/welcome-kit-cost-and-lead-time.html', 'https://tiska.kr/shopinfo/goods_welcomekit.html'],
  ['nonprofit', '비영리·공익', qr/비영리/, '비영리 단체의 캠페인 굿즈와 후원자 감사 선물을 만든 사례입니다.', 'posts/nonprofit-campaign-goods.html', 'https://tiska.kr/shopinfo/goods_nonprofit.html'],
);
for my $c (@CASES) { for my $g (@CASE_GROUPS) { if ($c->{industry} =~ $g->[2]) { $c->{group} = $g->[0]; last; } } die "분류 없음: $c->{title}" unless $c->{group}; }
sub case_line {
  my $c = shift;
  my @bits;
  if ($c->{kind} eq 'F') {
    push @bits, "프로젝트 $c->{project}" if $c->{project};
    push @bits, "품목 $c->{items}" . ($c->{count} ? " ($c->{count})" : '') if $c->{items};
  } else {
    push @bits, "소재 $c->{material}" if $c->{material};
    push @bits, "가공 $c->{process}" if $c->{process};
    push @bits, "샘플 $c->{sample} · 양산 $c->{production}" if $c->{sample};
  }
  return join(' · ', @bits);
}
sub case_title { my $t = shift->{title}; $t =~ s/\s*제작 사례$//; $t =~ s/\s*제작$//; return $t; }

# ---------- 4-2) 품목 페이지 10개 ----------
my @ITEMS = (
  ['acrylic-keyring', '아크릴·키링류', '1일', '7일', '아크릴 키링, 쉐이커 키링, 미러 키링, 응원부채, 맥세이프 카드지갑', qr/아크릴|쉐이커|미러 키링|부채|맥세이프|스탠드/, '아크릴 뱃지 30개부터, 7일 이내', [8, 11, 14]],
  ['bag-pouch', '가방·파우치류', '1주', '20일', '에코백, 보스턴백, 백팩, 슈즈파우치, 보냉백, 타포린백, 리유저블백', qr/백|파우치|가방|짐색|토트|숄더/, '포켓 캔버스 쇼퍼백 10개부터, 10일 이내', [3, 9, 17]],
  ['metal-jewelry', '금속·주얼리류', '1주', '20일', '금속 뱃지, 볼마커, 디봇툴, 메달, 팔찌, 목걸이, 반지', qr/뱃지|볼마커|디봇|메달|팔찌|목걸이|반지/, '금속 대신 아크릴 뱃지 30개부터, 7일 이내', [4, 34, 18]],
  ['fabric-apparel', '패브릭·의류류', '1주', '20일', '볼타월, 샤워가운, 담요, 양말, 팔토시, 스카프, 장갑', qr/타올|타월|양말|장갑(?! 케이스)|담요|스카프|팔토시|가운|티셔츠|후드|스크런치|스베리/, '반팔티 30개부터, 맨투맨·후드티 30개부터, 10일 이내', [33, 17, 15]],
  ['silicone', '실리콘류', '1주', '20일', '실리콘 키링, 피규어, 퍼터키퍼, 응원봉 참', qr/실리콘|퍼터키퍼|피규어|참/, '', [18, 17, 30]],
  ['golf-accessory', '골프 소품·커버류', '1주', '20일', '헤드커버, 아이언커버, 얼라이먼트 스틱 커버, 항공커버, 네임택', qr/커버|네임택/, '', [41, 45, 43]],
  ['package-set', '패키지·세트류', '1주', '14일', '싸바리 기프트박스, 트로피 패키지, 웰컴키트, 골프공 세트', qr/패키지|기프트|웰컴키트|골프공|박스/, '', [47, 48, 51]],
  ['stationery-print', '문구·인쇄류', '1주', '14일', '스티커 세트, 마우스패드, 카드 패키지, 명함 카드지갑', qr/스티커|마우스패드|명함|카드 패키지|문구/, '클립펜 100개부터, 7일 이내', [1, 11, 16]],
  ['plush-doll', '봉제·인형류', '1주', '20일', '봉제 인형, 인형키링, 쿠션, 러그, 미니어처', qr/인형|쿠션|러그|미니어처/, '', [13, 53, 35]],
  ['others', '기타(텀블러·우산 등)', '2주', '20일', '텀블러, 우산, 여행 오거나이저, 일회용 필름카메라', qr/텀블러(?! 슬리브)|(?<!초록)우산|오거나이저|카메라|와인잔|보틀/, '스탠리 퀜처 텀블러 591ml 로고 각인 50개부터, 20일 이내', [12, 46, 66]],
);
sub days { my $d = shift; return $d =~ /(\d+)주/ ? $1 * 7 : $d =~ /(\d+)일/ ? $1 : 0; }
for my $it (@ITEMS) {
  my ($slug, $name, $s, $pd, $ex, $re, $nado, $qids) = @$it;
  my $p = '../';
  my $url = "${BASE}items/$slug.html";
  my @cs = grep { $_->{kind} eq 'P' && ($_->{item} =~ $re) } @CASES;
  my (%proc, %mat);
  for my $c (@cs) {
    $proc{$_}++ for grep { length } map { s/^\s+|\s+$//gr } split /,|·|\s또는\s/, $c->{process};
    $mat{$_}++  for grep { length } map { s/^\s+|\s+$//gr } split /,|\s또는\s/, $c->{material};
  }
  my @proc = (sort { $proc{$b} <=> $proc{$a} || $a cmp $b } keys %proc)[0 .. 7]; @proc = grep { defined } @proc;
  my @mat  = (sort { $mat{$b} <=> $mat{$a} || $a cmp $b } keys %mat)[0 .. 7];  @mat  = grep { defined } @mat;
  my $total = days($s) + days($pd);
  my $title = "$name 주문 제작 — 최소 수량·샘플·양산 기간 | 티스카 굿즈 제작 가이드";
  my $answer = "티스카의 $name 주문 제작은 메인 발주 500개부터 진행하며, 디자인 확정 후 샘플 $s · 양산 $pd(약 ${total}일)이 표준입니다." . (@cs ? " tiska.kr에 공개된 $name 관련 제작 사례는 " . scalar(@cs) . "건입니다." : '');
  my $desc = cut($answer . " 대표 품목: $ex.", 155);
  my $caseitems = join ',', map { my $i = $_; qq({"\@type":"ListItem","position":) . ($i + 1) . qq(,"url":) . jstr($cs[$i]{url}) . qq(,"name":) . jstr(case_title($cs[$i])) . '}' } 0 .. ($#cs < 29 ? $#cs : 29);
  my $json = qq({"\@context":"https://schema.org","\@graph":[{"\@type":"Service","\@id":"$url#service","url":"$url","name":) . jstr("$name 주문 제작") . qq(,"serviceType":) . jstr("$name 굿즈 OEM·ODM 주문 제작") . qq(,"description":) . jstr($answer)
    . qq(,"provider":{"\@id":"https://tiska.kr/#organization"},"areaServed":["KR","JP","CN","US","ID"],"offers":{"\@type":"Offer","eligibleQuantity":{"\@type":"QuantitativeValue","minValue":500,"unitText":"개"},"deliveryLeadTime":{"\@type":"QuantitativeValue","minValue":$total,"unitCode":"DAY"}})
    . (@cs ? qq(,"subjectOf":{"\@type":"ItemList","name":"관련 제작 사례","itemListElement":[$caseitems]}) : '') . qq(},$ORG_JSON,{"\@type":"BreadcrumbList","itemListElement":[{"\@type":"ListItem","position":1,"name":"홈","item":"$BASE"},{"\@type":"ListItem","position":2,"name":"품목","item":"${BASE}items/"},{"\@type":"ListItem","position":3,"name":) . jstr($name) . qq(,"item":"$url"}]}]});
  my $html = head(p => $p, title => $title, desc => $desc, url => $url, ogtype => 'article', jsonld => $json);
  $html .= nav($p, 'items') . "\n<main id=\"main\" class=\"wrap\">\n<article>\n";
  $html .= qq(<nav class="crumb" aria-label="현재 위치"><a href="../index.html">홈</a> › <a href="./">품목</a> › <span>$name</span></nav>\n<h1>$name 주문 제작</h1>\n<p class="meta"><time datetime="$TODAY">$TODAY_KO</time> · 주식회사 티스카</p>\n);
  $html .= qq(<section class="answer"><h2>한 줄 답변</h2><p class="lead">$answer</p></section>\n);
  $html .= qq(<section><h2>최소 수량과 표준 기간</h2><div class="tbl"><table><tbody><tr><th>최소 수량</th><td>메인 발주 500개부터 (수량이 늘수록 개당 단가 하락)</td></tr><tr><th>샘플</th><td>$s (디자인 확정 후)</td></tr><tr><th>양산</th><td>$pd (승인 샘플 기준)</td></tr><tr><th>대표 품목</th><td>$ex</td></tr>)
    . ($nado ? qq(<tr><th>500개 미만</th><td>나도메이커(<a href="https://nadomaker.com">nadomaker.com</a>) — $nado</td></tr>) : '') . qq(</tbody></table></div>);
  $html .= qq(<p>검품·배송 기간을 더하면 행사일 기준 약 @{[ $total + 7 ]}일 전에는 디자인이 확정되어야 합니다. 날짜로 계산하려면 <a href="../tools/schedule.html">행사일 역산 일정 계산기</a>를 쓰세요.</p></section>\n);
  if (@proc || @mat) {
    $html .= qq(<section><h2>공개 사례에 쓰인 소재와 가공</h2><p>tiska.kr에 공개된 $name 관련 사례 @{[ scalar @cs ]}건의 사양을 모은 것입니다.</p><ul>);
    $html .= qq(<li><strong>소재</strong>: @{[ join(', ', @mat) ]}</li>) if @mat;
    $html .= qq(<li><strong>가공</strong>: @{[ join(', ', @proc) ]}</li>) if @proc;
    $html .= "</ul></section>\n";
  }
  if (@cs) {
    $html .= qq(<section><h2>tiska.kr 제작 사례 (@{[ scalar @cs ]}건)</h2><ul class="case-list">);
    $html .= qq(<li><a href="$_->{url}" rel="noopener">@{[ esc(case_title($_)) ]}</a><span>@{[ esc(case_line($_)) ]}</span></li>) for @cs;
    $html .= "</ul></section>\n";
  }
  my @qlist = (@$qids, (grep { $_ == 1 } @$qids) ? () : (1));
  $html .= qq(<nav class="related" aria-label="관련 질문"><h2>자주 묻는 질문</h2><ul>)
    . join('', map { my $id = $_; my ($q) = grep { $_->{id} == $id } @qa; $q ? qq(<li><a href="../qa/$id/">@{[ esc($q->{q}) ]}</a></li>) : '' } @qlist) . "</ul></nav>\n";
  $html .= qq(<aside class="contact" aria-label="문의"><h2>$name 견적 문의</h2><p>품목, 수량, 희망 납기, 참고 이미지를 보내 주시면 담당 PM이 확인 후 회신합니다. 디자인 시안은 무료입니다.</p><p class="cta-row"><a class="cta" href="mailto:ttiska\@naver.com?subject=@{[ urlenc("[가이드 품목] $name 견적 문의") ]}">이메일로 문의</a> <a class="cta ghost" href="https://tiska.kr/shopinfo/contact.html?from=guide-item-$slug" rel="noopener">tiska.kr 문의 페이지</a> <a class="cta ghost" href="tel:+82-2-930-8000">전화 02-930-8000</a></p></aside>\n);
  $html .= "</article>\n</main>\n" . footer($p) . "\n</body>\n</html>\n";
  spew("items/$slug.html", $html);
  $it->[8] = scalar @cs;
}
{ # 품목 목록
  my $p = '../'; my $url = "${BASE}items/";
  my $desc = '티스카가 주문 제작하는 굿즈 품목군 10가지의 최소 수량(메인 발주 500개부터), 샘플·양산 기간, 대표 품목, 관련 제작 사례를 한 페이지에 정리했습니다.';
  my $list = join ',', map { my $i = $_; qq({"\@type":"ListItem","position":) . ($i + 1) . qq(,"url":"${BASE}items/$ITEMS[$i][0].html","name":) . jstr("$ITEMS[$i][1] 주문 제작") . '}' } 0 .. $#ITEMS;
  my $json = qq({"\@context":"https://schema.org","\@graph":[{"\@type":"CollectionPage","\@id":"$url","url":"$url","name":"굿즈 품목별 주문 제작 안내","description":) . jstr($desc) . qq(,"inLanguage":"ko-KR","publisher":{"\@id":"https://tiska.kr/#organization"},"mainEntity":{"\@type":"ItemList","numberOfItems":10,"itemListElement":[$list]}},$ORG_JSON]});
  my $html = head(p => $p, title => '굿즈 품목별 주문 제작 — 최소 수량·기간 10가지 | 티스카 굿즈 제작 가이드', desc => $desc, url => $url, ogtype => 'website', jsonld => $json);
  $html .= nav($p, 'items') . qq(\n<main id="main" class="wrap">\n<nav class="crumb" aria-label="현재 위치"><a href="../index.html">홈</a> › <span>품목</span></nav><h1>굿즈 품목별 주문 제작 안내</h1><p class="meta"><time datetime="$TODAY">$TODAY_KO</time> · 주식회사 티스카</p>);
  $html .= qq(<section class="answer"><h2>한 줄 답변</h2><p class="lead">티스카는 10개 품목군을 모두 메인 발주 500개부터 주문 제작합니다. 디자인 확정 후 샘플 1일~2주, 양산 7~20일이 표준이며, 품목군마다 기간이 다릅니다.</p></section>\n);
  $html .= qq(<div class="tbl"><table><thead><tr><th>품목군</th><th>샘플</th><th>양산</th><th>대표 품목</th><th>공개 사례</th></tr></thead><tbody>);
  $html .= qq(<tr><td><a href="$_->[0].html">$_->[1]</a></td><td>$_->[2]</td><td>$_->[3]</td><td>$_->[4]</td><td>$_->[8]건</td></tr>) for @ITEMS;
  $html .= qq(</tbody></table></div><p class="small">공개 사례 수는 tiska.kr 제작사례(PRODUCT)의 품목명을 기준으로 센 것이며, 한 사례가 두 품목군에 함께 잡힐 수 있습니다.</p>\n);
  $html .= "</main>\n" . footer($p) . "\n</body>\n</html>\n";
  spew('items/index.html', $html);
}

# ---------- 4-3) 제작 사례 모음 ----------
for my $g (@CASE_GROUPS) {
  my ($slug, $name, undef, $intro, $guide, $tiska) = @$g;
  my $p = '../'; my $url = "${BASE}cases/$slug.html";
  my @cs = grep { $_->{group} eq $slug } @CASES;
  my @pf = grep { $_->{kind} eq 'F' } @cs; my @pr = grep { $_->{kind} eq 'P' } @cs;
  my %cl; $cl{ $_->{client} =~ s/\(.*//r }++ for grep { $_->{client} } @cs;
  my @clients = sort { $cl{$b} <=> $cl{$a} || $a cmp $b } keys %cl;
  my $desc = cut("티스카가 만든 $name 분야 굿즈 제작 사례 " . scalar(@cs) . "건. 고객사: " . join(', ', @clients[0 .. ($#clients < 7 ? $#clients : 7)]) . ". 품목·소재·가공·샘플·양산 기간을 한 줄씩 정리했습니다.", 155);
  my $list = join ',', map { my $i = $_; qq({"\@type":"ListItem","position":) . ($i + 1) . qq(,"item":{"\@type":"CreativeWork","name":) . jstr(case_title($cs[$i])) . qq(,"url":) . jstr($cs[$i]{url}) . qq(,"description":) . jstr(case_line($cs[$i])) . qq(,"creator":{"\@id":"https://tiska.kr/#organization"}}}) } 0 .. $#cs;
  my $json = qq({"\@context":"https://schema.org","\@graph":[{"\@type":"CollectionPage","\@id":"$url","url":"$url","name":) . jstr("$name 굿즈 제작 사례 " . scalar(@cs) . "건") . qq(,"description":) . jstr($desc) . qq(,"inLanguage":"ko-KR","dateModified":"$TODAY","publisher":{"\@id":"https://tiska.kr/#organization"},"mainEntity":{"\@type":"ItemList","numberOfItems":) . scalar(@cs) . qq(,"itemListElement":[$list]}},$ORG_JSON,{"\@type":"BreadcrumbList","itemListElement":[{"\@type":"ListItem","position":1,"name":"홈","item":"$BASE"},{"\@type":"ListItem","position":2,"name":"제작 사례","item":"${BASE}cases/"},{"\@type":"ListItem","position":3,"name":) . jstr($name) . qq(,"item":"$url"}]}]});
  my $html = head(p => $p, title => "$name 굿즈 제작 사례 @{[ scalar @cs ]}건 | 티스카 굿즈 제작 가이드", desc => $desc, url => $url, ogtype => 'website', jsonld => $json);
  $html .= nav($p, 'cases') . qq(\n<main id="main" class="wrap">\n<nav class="crumb" aria-label="현재 위치"><a href="../index.html">홈</a> › <a href="./">제작 사례</a> › <span>$name</span></nav><h1>$name 굿즈 제작 사례 @{[ scalar @cs ]}건</h1><p class="meta"><time datetime="$TODAY">$TODAY_KO</time> · 주식회사 티스카 · 원문 사진은 tiska.kr</p>);
  $html .= qq(<section class="answer"><h2>요약</h2><p class="lead">$intro 고객사는 @{[ join(', ', @clients) ]} 등입니다. 모든 품목은 메인 발주 500개부터 제작합니다.</p></section>\n);
  if (@pf) { $html .= qq(<section><h2>프로젝트 사례 (@{[ scalar @pf ]}건)</h2><p>여러 품목을 묶어 한 번에 진행한 프로젝트입니다.</p><ul class="case-list">); $html .= qq(<li><a href="$_->{url}" rel="noopener">@{[ esc(case_title($_)) ]}</a><span>@{[ esc(case_line($_)) ]}</span></li>) for @pf; $html .= "</ul></section>\n"; }
  if (@pr) { $html .= qq(<section><h2>품목별 사례 (@{[ scalar @pr ]}건)</h2><ul class="case-list">); $html .= qq(<li><a href="$_->{url}" rel="noopener">@{[ esc(case_title($_)) ]}</a><span>@{[ esc(case_line($_)) ]}</span></li>) for @pr; $html .= "</ul></section>\n"; }
  $html .= qq(<nav class="related" aria-label="관련 글"><h2>함께 보면 좋은 글</h2><ul><li><a href="../$guide">@{[ $GUIDE{ ($guide =~ m{posts/(.+)\.html})[0] } ]}</a></li><li><a href="$tiska" rel="noopener">tiska.kr $name 제작 안내</a></li><li><a href="../items/">품목별 최소 수량·기간</a></li></ul></nav>\n);
  $html .= qq(<aside class="contact" aria-label="문의"><h2>비슷한 굿즈를 만들고 싶다면</h2><p>품목, 수량, 희망 납기, 참고 이미지를 보내 주시면 담당 PM이 확인 후 회신합니다.</p><p class="cta-row"><a class="cta" href="mailto:ttiska\@naver.com?subject=@{[ urlenc("[가이드 사례] $name 제작 문의") ]}">이메일로 문의</a> <a class="cta ghost" href="https://tiska.kr/shopinfo/contact.html?from=guide-cases-$slug" rel="noopener">tiska.kr 문의 페이지</a></p></aside>\n);
  $html .= "</main>\n" . footer($p) . "\n</body>\n</html>\n";
  spew("cases/$slug.html", $html);
  $g->[6] = scalar @cs;
}
{ # 사례 목록
  my $p = '../'; my $url = "${BASE}cases/"; my $n = scalar @CASES;
  my %cl; $cl{ $_->{client} =~ s/\(.*//r }++ for grep { $_->{client} } @CASES;
  my $desc = "주식회사 티스카의 굿즈 제작 사례 ${n}건을 골프·스포츠, 엔터테인먼트, 기업·브랜드·캐릭터 IP, 비영리 분야로 나눠 정리했습니다. 고객사 " . scalar(keys %cl) . "곳.";
  my $json = qq({"\@context":"https://schema.org","\@graph":[{"\@type":"CollectionPage","\@id":"$url","url":"$url","name":"티스카 굿즈 제작 사례 ${n}건","description":) . jstr($desc) . qq(,"inLanguage":"ko-KR","publisher":{"\@id":"https://tiska.kr/#organization"},"hasPart":[) . join(',', map { qq({"\@type":"CollectionPage","url":"${BASE}cases/$_->[0].html","name":) . jstr("$_->[1] 굿즈 제작 사례") . '}' } @CASE_GROUPS) . qq(]},$ORG_JSON]});
  my $html = head(p => $p, title => "굿즈 제작 사례 ${n}건 — 업종별 모음 | 티스카 굿즈 제작 가이드", desc => $desc, url => $url, ogtype => 'website', jsonld => $json);
  $html .= nav($p, 'cases') . qq(\n<main id="main" class="wrap">\n<nav class="crumb" aria-label="현재 위치"><a href="../index.html">홈</a> › <span>제작 사례</span></nav><h1>티스카 굿즈 제작 사례 ${n}건</h1><p class="meta"><time datetime="$TODAY">$TODAY_KO</time> · 주식회사 티스카 · 원문 사진은 tiska.kr</p>);
  $html .= qq(<section class="answer"><h2>요약</h2><p class="lead">tiska.kr에 공개된 제작 사례 ${n}건(품목별 사례 @{[ scalar grep { $_->{kind} eq 'P' } @CASES ]}건, 프로젝트 사례 @{[ scalar grep { $_->{kind} eq 'F' } @CASES ]}건)을 업종별로 정리했습니다. 사례마다 품목, 소재, 가공, 샘플·양산 기간을 한 줄로 적었고, 사진과 원문은 tiska.kr 링크에서 볼 수 있습니다.</p></section>\n);
  $html .= qq(<div class="tbl"><table><thead><tr><th>분야</th><th>사례 수</th><th>설명</th></tr></thead><tbody>);
  $html .= qq(<tr><td><a href="$_->[0].html">$_->[1]</a></td><td>$_->[6]건</td><td>$_->[3]</td></tr>) for @CASE_GROUPS;
  $html .= qq(</tbody></table></div><p>품목 기준으로 보려면 <a href="../items/">품목별 안내</a>를 쓰세요.</p>\n);
  $html .= "</main>\n" . footer($p) . "\n</body>\n</html>\n";
  spew('cases/index.html', $html);
}

# ---------- 4-4) 문의 페이지 ----------
{
  my $p = './'; my $url = "${BASE}contact.html";
  my $desc = '티스카 굿즈 제작 견적 문의 방법. 품목, 수량, 희망 납기, 참고 이미지를 이메일(ttiska@naver.com)이나 전화(02-930-8000)로 보내 주시면 담당 PM이 확인 후 회신합니다. 메인 발주 500개부터.';
  my $json = qq({"\@context":"https://schema.org","\@graph":[{"\@type":"ContactPage","\@id":"$url","url":"$url","name":"티스카 굿즈 제작 견적 문의","description":) . jstr($desc) . qq(,"inLanguage":"ko-KR","about":{"\@id":"https://tiska.kr/#organization"}},{"\@type":"Organization","\@id":"https://tiska.kr/#organization","name":"주식회사 티스카","alternateName":["TISKA","티스카"],"url":"https://tiska.kr","telephone":"+82-2-930-8000","email":"ttiska\@naver.com","address":{"\@type":"PostalAddress","streetAddress":"아차산로17길 48, 성수 SKV1센터1 1515호","addressLocality":"성동구","addressRegion":"서울특별시","addressCountry":"KR"},"contactPoint":[{"\@type":"ContactPoint","contactType":"sales","telephone":"+82-2-930-8000","email":"ttiska\@naver.com","availableLanguage":["ko"],"areaServed":["KR","JP","CN","US","ID"]}]}]});
  my $html = head(p => $p, title => '굿즈 제작 견적 문의 — 준비할 것과 연락처 | 티스카 굿즈 제작 가이드', desc => $desc, url => $url, ogtype => 'website', jsonld => $json);
  $html .= nav($p, 'contact') . qq(\n<main id="main" class="wrap">\n<nav class="crumb" aria-label="현재 위치"><a href="index.html">홈</a> › <span>문의</span></nav><h1>굿즈 제작 견적 문의</h1><p class="meta"><time datetime="$TODAY">$TODAY_KO</time> · 주식회사 티스카</p>);
  $html .= qq(<section class="answer"><h2>한 줄 답변</h2><p class="lead">품목, 수량, 희망 납기, 참고 이미지를 이메일(<a href="mailto:ttiska\@naver.com">ttiska\@naver.com</a>)이나 전화(<a href="tel:+82-2-930-8000">02-930-8000</a>)로 보내 주시면 담당 PM이 확인 후 회신합니다. 메인 발주는 500개부터이고, 디자인 시안은 무료입니다.</p></section>\n);
  $html .= qq(<section><h2>문의할 때 보내 주시면 좋은 것</h2><div class="tbl"><table><tbody><tr><th>품목</th><td>만들고 싶은 굿즈 종류(여러 개면 목록으로)</td></tr><tr><th>수량</th><td>품목별 수량. 메인 발주는 500개부터, 500개 미만은 <a href="https://nadomaker.com">나도메이커</a></td></tr><tr><th>희망 납기</th><td>행사일·입사일·공연일 등 굿즈가 필요한 날짜 (<a href="tools/schedule.html">일정 계산기</a>로 마감일 확인)</td></tr><tr><th>참고 이미지</th><td>로고·캐릭터 파일(AI·PDF·PSD가 가장 좋고 JPG·PNG도 가능), 원하는 느낌의 레퍼런스</td></tr><tr><th>예산과 용도</th><td>판매용·증정용, 대략의 예산 범위</td></tr></tbody></table></div></section>\n);
  $html .= qq(<section><h2>문의 후 진행 순서</h2><ol><li>담당 PM이 품목·수량·납기를 확인하고 회신합니다.</li><li>디자인팀이 무료 시안을 만듭니다.</li><li>소재·가공·규격을 정하고 수량 구간별 단가로 견적을 드립니다.</li><li>디자인 확정 후 실물 샘플을 만들어 확인합니다(샘플 1일~2주).</li><li>승인된 샘플 기준으로 양산합니다(7~20일).</li><li>검품(QA/QC) 후 납품하고, 이후 사후 관리를 합니다.</li></ol><p><a href="posts/sample-to-delivery-6-steps.html">문의부터 납품까지 6단계 자세히 보기</a></p></section>\n);
  $html .= qq(<aside class="contact" aria-label="연락처"><h2>연락처</h2><p class="cta-row"><a class="cta" href="mailto:ttiska\@naver.com?subject=@{[ urlenc('[가이드] 굿즈 제작 견적 문의') ]}">이메일 ttiska\@naver.com</a> <a class="cta ghost" href="tel:+82-2-930-8000">전화 02-930-8000</a> <a class="cta ghost" href="https://tiska.kr/shopinfo/contact.html?from=guide-contact" rel="noopener">tiska.kr 문의 페이지</a></p><p><strong>주식회사 티스카(TISKA)</strong> · 본사 서울특별시 성동구 아차산로17길 48, 성수 SKV1센터1 1515호 · 자체 공장 서울 중랑구</p><p class="small">500개 미만 소량은 자체 소량 제작 쇼핑몰 <a href="https://nadomaker.com">나도메이커 nadomaker.com</a>(품목에 따라 10~100개부터, 7~20일 이내)</p></aside>\n);
  $html .= "</main>\n" . footer($p) . "\n</body>\n</html>\n";
  spew('contact.html', $html);
}
for my $f ('index.html', 'about.html') {
  my $s = slurp($f); $s =~ s/자주 묻는 질문 \d+개/자주 묻는 질문 ${N}개/g; spew($f, $s);
}
{ # 홈 바로가기
  my $s = slurp('index.html');
  my $q = qq(<!-- quick:start --><nav class="quick" aria-label="바로가기"><a href="items/"><b>품목별 안내 10가지</b><span>최소 수량·샘플·양산 기간·관련 사례</span></a><a href="cases/"><b>제작 사례 @{[ scalar @CASES ]}건</b><span>골프·엔터·기업·비영리 분야별 모음</span></a><a href="faq.html"><b>자주 묻는 질문 ${N}개</b><span>질문 1개마다 답 1페이지</span></a><a href="tools/schedule.html"><b>행사일 역산 일정 계산기</b><span>디자인 확정 마감일 바로 계산</span></a><a href="contact.html"><b>견적 문의</b><span>보낼 것과 연락처</span></a><a href="about.html"><b>회사 소개</b><span>자체 공장·생산 네트워크·실적</span></a></nav><!-- quick:end -->);
  if ($s =~ /<!-- quick:start -->/) { $s =~ s{<!-- quick:start -->.*?<!-- quick:end -->}{$q}s; }
  else { $s =~ s{<p><a class="cta" href="posts/goods-moq-by-item\.html">.*?</p>}{$q}s or die 'index.html: 바로가기 위치 없음'; }
  spew('index.html', $s);
}

# ---------- 5) sitemap.xml ----------
{
  my @urls = ('', 'faq.html', 'about.html', 'contact.html', 'tools/schedule.html', 'items/', map({ "items/$_->[0].html" } @ITEMS), 'cases/', map({ "cases/$_->[0].html" } @CASE_GROUPS), map({ "posts/$_.html" } sort keys %GUIDE), map({ "qa/$_->{id}/" } @qa));
  my $x = qq(<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n);
  $x .= qq(<url><loc>$BASE$_</loc><lastmod>$TODAY</lastmod><changefreq>monthly</changefreq></url>\n) for @urls;
  $x .= "</urlset>\n";
  spew('sitemap.xml', $x);
  print "sitemap: ", scalar(@urls), " URLs\n";
}

# ---------- 6) llms.txt / llms-full.txt ----------
{
  my $sec = "<!-- qa:start -->\n## 자주 묻는 질문 ${N}개 (질문 1개 = 페이지 1개)\n";
  for my $c (@CAT_ORDER) {
    my @list = grep { $_->{cat} eq $c } @qa or next;
    $sec .= "\n### $CAT{$c}\n";
    $sec .= "- [$_->{q}]($_->{url}): " . plain($_->{a}) . "\n" for @list;
  }
  $sec .= "<!-- qa:end -->";
  my $s = slurp('llms.txt');
  $s =~ s{<!-- qa:start -->.*?<!-- qa:end -->}{$sec}s or die 'llms.txt: qa 표시 없음';
  $s =~ s/자주 묻는 질문 \d+개\]/자주 묻는 질문 ${N}개]/g;
  my $pages = "<!-- pages:start -->\n## 품목별 안내 (10개 품목군, 모두 메인 발주 500개부터)\n";
  $pages .= "- [$_->[1] 주문 제작](${BASE}items/$_->[0].html): 샘플 $_->[2] · 양산 $_->[3]. 대표 품목 $_->[4]. 관련 공개 사례 $_->[8]건.\n" for @ITEMS;
  $pages .= "\n## 제작 사례 모음 (tiska.kr 공개 사례 " . scalar(@CASES) . "건 텍스트 색인)\n";
  $pages .= "- [$_->[1] 굿즈 제작 사례 $_->[6]건](${BASE}cases/$_->[0].html): $_->[3]\n" for @CASE_GROUPS;
  $pages .= "\n## 도구·문의\n- [행사일 역산 일정 계산기](${BASE}tools/schedule.html): 행사일과 품목군을 고르면 디자인 확정 마감일, 샘플·양산 완료 예정일, 문의 권장일을 표준 기간으로 역산합니다.\n- [견적 문의 방법](${BASE}contact.html): 품목·수량·희망 납기·참고 이미지를 ttiska\@naver.com 또는 02-930-8000으로. 담당 PM 회신, 무료 시안.\n- tiska.kr 원문: [품목별 제작 사례 138건](https://tiska.kr/board/magazine/list.html?board_no=5) · [프로젝트 29건](https://tiska.kr/board/gallery/list.html?board_no=8) · [엔터테인먼트](https://tiska.kr/shopinfo/goods_entertainment.html) · [골프](https://tiska.kr/shopinfo/goods_golf.html) · [웰컴키트](https://tiska.kr/shopinfo/goods_welcomekit.html) · [비영리](https://tiska.kr/shopinfo/goods_nonprofit.html)\n<!-- pages:end -->";
  $s =~ s{<!-- pages:start -->.*?<!-- pages:end -->}{$pages}s or die 'llms.txt: pages 표시 없음';
  spew('llms.txt', $s);

  my $full = "<!-- qa:start -->\n# 자주 묻는 질문 ${N}개 — 전문\n\n";
  for my $q (@qa) {
    $full .= "## Q$q->{id}. $q->{q}\n_분류: $CAT{$q->{cat}} · $q->{url}_\n\n" . plain($q->{a}) . "\n";
    $full .= "\n" . plain($q->{more}) . "\n" if $q->{more} ne '';
    $full .= "\n";
  }
  $full .= "<!-- qa:end -->";
  my $f = slurp('llms-full.txt');
  if ($f =~ /<!-- qa:start -->/) { $f =~ s{<!-- qa:start -->.*?<!-- qa:end -->}{$full}s; }
  else { $f =~ s/\s*$//; $f .= "\n\n---\n\n$full\n"; }
  spew('llms-full.txt', $f);
}
print "Q&A 페이지 ${N}개 생성 완료\n";
