#!/usr/bin/perl
# 티스카 굿즈 제작 가이드 — 글(posts) 빌더 (저장소 안에서 실행)
# 사용:  perl _build/posts_build.pl          (저장소 어느 위치에서 실행해도 됨)
# 입력:  _src/posts.tsv  (글 목록: n, file, slug, reader, short, date, time — 탭 구분, 첫 줄 헤더)
#        _src/content/*.md (발행 메모 인용 블록 포함 마크다운 원고)
# 출력:  posts/{slug}.html, posts/{slug}.md, index.html, rss.xml,
#        llms.txt(## 가이드 글 구역만 교체), llms-full.txt(가이드 전문 재생성 + 기존 Q&A 구역 유지), og/_titles.tsv
# 이어서 반드시  perl _build/build.pl  을 실행해 메뉴·바로가기·Q&A 링크·faq·sitemap·llms Q&A 구역을 갱신한다.
use strict; use warnings; use utf8;
use open qw(:std :encoding(UTF-8));
use File::Path qw(make_path);
use File::Basename qw(dirname);
use POSIX qw(ceil strftime);
use Time::Local qw(timegm);

my $ROOT = dirname(dirname(__FILE__));
chdir $ROOT or die "cannot chdir $ROOT";

my $BASE = 'https://ohyoumeee-prog.github.io/tiska-guide';
my $SRC  = '_src/content';
my $MANIFEST = '_src/posts.tsv';

my $SITE     = '티스카 굿즈 제작 가이드';
my $TAGLINE  = '굿즈·MD 주문 제작, 담당자가 묻는 질문에 숫자로 답합니다.';
my $FACT_DATE    = '2026-11-11';
my $FACT_DATE_KO = '2026년 11월 11일';
my $ORG      = '주식회사 티스카';
my $ORG_URL  = 'https://tiska.kr';
my $SITE_DESC = '주식회사 티스카가 운영하는 굿즈·MD 주문 제작 가이드. 품목별 최소 수량, 샘플·양산 기간, 비용 구조, 진행 절차를 담당자가 실제로 묻는 질문 형식으로 숫자와 함께 정리합니다.';
my $EMAIL    = 'ttiska' . '@' . 'naver.com';
my $HEAD_EXTRA = -f '_src/head_extra.html' ? do { local $/; open my $fh, '<', '_src/head_extra.html'; my $x = <$fh>; close $fh; $x =~ s/^\x{FEFF}//; $x } : '';

# ---------- 유틸 ----------
sub slurp { my $f = shift; open my $fh, '<', $f or die "읽기 실패 $f: $!"; local $/; my $s = <$fh>; close $fh; $s =~ s/^\x{FEFF}//; return $s }
sub spit  { my ($f, $s) = @_; my ($d) = $f =~ m{^(.*)/}; make_path($d) if $d && !-d $d; open my $fh, '>', $f or die "쓰기 실패 $f: $!"; print $fh $s; close $fh }
sub esc { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; return $s }
sub j   { my $s = shift // ''; $s =~ s/\\/\\\\/g; $s =~ s/"/\\"/g; $s =~ s/\r//g; $s =~ s/\n/\\n/g; $s =~ s/\t/\\t/g; $s =~ s/</\\u003c/g; return $s }
sub strip { my $s = shift // ''; $s =~ s/<[^>]+>//g; $s =~ s/&amp;/&/g; $s =~ s/&lt;/</g; $s =~ s/&gt;/>/g; $s =~ s/&quot;/"/g; return $s }
sub plain_md { my $s = shift // ''; $s =~ s/\*\*(.+?)\*\*/$1/g; return $s }
sub ko_date { my ($d) = @_; my ($y, $m, $dd) = split /-/, $d; return sprintf('%d년 %d월 %d일', $y, $m, $dd) }
sub rfc_date { # 'YYYY-MM-DD','HH:MM' → 'Mon, 23 Nov 2026 16:00:00 +0900'
  my ($d, $t) = @_; my ($y, $m, $dd) = split /-/, $d; my ($hh, $mi) = split /:/, $t;
  my $epoch = timegm(0, $mi, $hh, $dd, $m - 1, $y);
  return strftime('%a, %d %b %Y %H:%M:%S +0900', gmtime($epoch));
}

# ---------- 글 목록 ----------
my @POSTS;
{
  my @lines = grep { /\S/ } split /\r?\n/, slurp($MANIFEST);
  my @hdr = split /\t/, shift @lines;
  for my $l (@lines) {
    next if $l =~ /^#/;
    my @c = split /\t/, $l;
    my %p; @p{@hdr} = @c;
    for (qw(n file slug reader short date time)) { die "posts.tsv: '$_' 값이 비어 있음: $l" unless defined $p{$_} && length $p{$_} }
    $p{kind} = 'guide' unless defined $p{kind} && length $p{kind};   # guide(가이드 글) | case(제작 사례 글)
    die "posts.tsv: 날짜 형식 오류 $p{date}" unless $p{date} =~ /^\d{4}-\d{2}-\d{2}$/;
    die "posts.tsv: 시각 형식 오류 $p{time}" unless $p{time} =~ /^\d{2}:\d{2}$/;
    die "posts.tsv: 원고 없음 $SRC/$p{file}" unless -f "$SRC/$p{file}";
    push @POSTS, \%p;
  }
}
my %SLUG; for (@POSTS) { die "slug 중복: $_->{slug}" if $SLUG{$_->{slug}}++ }
my %BYN = map { $_->{n} => $_ } @POSTS;
for my $p (@POSTS) {
  $p->{iso}     = "$p->{date}T$p->{time}:00+09:00";
  $p->{date_ko} = ko_date($p->{date});
  $p->{rfc}     = rfc_date($p->{date}, $p->{time});
  $p->{sort}    = "$p->{date} $p->{time} $p->{n}";
}
my @NEWEST = sort { $b->{sort} cmp $a->{sort} } @POSTS;   # 최신 글이 앞

sub inline {
  my $s = esc(shift);
  my @u;
  $s =~ s{(https?://[^\s<>()"\x{201C}\x{201D}\x{300C}\x{300D}\x{FF08}\x{FF09}]+)}{ push @u, $1; "\x{1}" . $#u . "\x{2}" }ge;
  $s =~ s{\*\*(.+?)\*\*}{<strong>$1</strong>}g;
  $s =~ s{(?<![\w/.@-])(nadomaker\.com|tiska\.kr)(?![\w/.-])}{<a href="https://$1">$1</a>}g;
  $s =~ s{\x{1}(\d+)\x{2}}{ my $x = $u[$1]; "<a href=\"$x\">$x</a>" }ge;
  $s =~ s{\Q$EMAIL\E}{<a href="mailto:$EMAIL">$EMAIL</a>}g;
  $s =~ s{(?<![\d-])(02-930-8000)(?![\d-])}{<a href="tel:+82-2-930-8000">$1</a>}g;
  return $s;
}

# ---------- 마크다운 파싱 ----------
sub parse_post {
  my ($p) = @_;
  my @L = split /\r?\n/, slurp("$SRC/$p->{file}");
  my ($title) = grep { /^#\s/ } @L; die "$p->{file}: 제목(# ) 없음" unless defined $title; $title =~ s/^#\s+//; $p->{title} = $title;
  my ($bi) = grep { $L[$_] =~ /^##\s/ } 0..$#L; die "$p->{file}: 소제목(## ) 없음" unless defined $bi;
  my @memo = map { my $x = $_; $x =~ s/^>\s?//; $x } grep { /^>/ } @L[0..$bi-1];
  my (@q, $desc, @links);
  for (@memo) {
    if (/목표 질의:\s*(.+)/)          { push @q, ($1 =~ /"([^"]+)"/g) }
    elsif (/메타 설명[^:]*:\s*(.+)/)  { $desc = $1 }
    elsif (/내부 링크:\s*(.+)/)       { push @links, ($1 =~ /(\d{2})\(/g) }
    elsif (/대표 이미지:\s*(\S+)/)     { $p->{cover} = $1 }   # posts/ 기준 상대 경로(예: img/p_203_01.jpg) → og:image
  }
  $p->{queries} = \@q; $p->{desc} = $desc // ''; $p->{links} = \@links;
  die "$p->{file}: 발행 메모에 '메타 설명' 없음" unless length $p->{desc};
  my ($hi) = grep { $L[$_] =~ /^---\s*$/ } $bi..$#L; $hi //= scalar(@L);
  my @body = @L[$bi..$hi-1];
  while (@body && $body[-1] =~ /^\s*$/) { pop @body }

  my (@sec, $cur, $list, $table, $fq);
  my $flush_list  = sub { if ($list)  { $cur->{html} .= "</$list>\n"; $list = undef } };
  my $flush_table = sub { if ($table) { $cur->{html} .= "</tbody></table></div>\n"; $table = 0 } };
  my $flush_q = sub {
    return unless $fq;
    push @{$cur->{faq}}, $fq;
    $cur->{html} .= qq{<div class="faq-item"><h3>} . inline($fq->{q}) . qq{</h3>}
      . join('', map { '<p>' . inline($_) . '</p>' } @{$fq->{a}}) . "</div>\n";
    $fq = undef;
  };
  for my $l (@body) {
    if ($l =~ /^##\s+(.+)/) {
      $flush_list->(); $flush_table->(); $flush_q->();
      push @sec, $cur if $cur;
      my $t = $1;
      my $kind = $t eq '자주 묻는 질문' ? 'faq' : $t eq '한 줄 답변' ? 'answer' : 'body';
      my $nbody = 1 + scalar grep { $_->{kind} eq 'body' } @sec;
      $cur = { title=>$t, kind=>$kind, html=>'', faq=>[], id=> $kind eq 'faq' ? 'faq' : $kind eq 'answer' ? 'answer' : "sec-$nbody" };
      next;
    }
    next unless $cur;
    if ($l =~ /^\s*$/) { $flush_list->(); $flush_table->(); $flush_q->() if $cur->{kind} eq 'faq'; next }
    if ($l =~ /^!\[([^\]]*)\]\(([^)\s]+)\)\s*$/) {   # 이미지 한 줄: ![설명](img/파일.jpg)
      my ($alt, $src) = ($1, $2); $flush_list->(); $flush_table->();
      $cur->{html} .= qq{<figure class="photo"><img src="} . esc($src) . qq{" alt="} . esc($alt) . qq{" loading="lazy"><figcaption>} . esc($alt) . qq{</figcaption></figure>\n};
      next;
    }
    if ($l =~ /^\|/) {
      $flush_list->();
      next if $l =~ /^\|[\s:|-]+\|?\s*$/;
      my @c = split /\s*\|\s*/, $l; shift @c while @c && $c[0] eq '';
      if (!$table) {
        $table = 1;
        $cur->{html} .= qq{<div class="tbl"><table><thead><tr>} . join('', map { '<th>' . inline($_) . '</th>' } @c) . "</tr></thead><tbody>\n";
      } else {
        $cur->{html} .= '<tr>' . join('', map { '<td>' . inline($_) . '</td>' } @c) . "</tr>\n";
      }
      next;
    }
    $flush_table->();
    if ($l =~ /^-\s+(.+)/)      { my $t = $1; if (($list // '') ne 'ul') { $flush_list->(); $list = 'ul'; $cur->{html} .= "<ul>\n" } $cur->{html} .= '<li>' . inline($t) . "</li>\n"; next }
    if ($l =~ /^\d+\.\s+(.+)/)  { my $t = $1; if (($list // '') ne 'ol') { $flush_list->(); $list = 'ol'; $cur->{html} .= "<ol>\n" } $cur->{html} .= '<li>' . inline($t) . "</li>\n"; next }
    $flush_list->();
    if ($cur->{kind} eq 'faq' && $l =~ /^\*\*Q\.\s*(.+?)\*\*\s*$/) { $flush_q->(); $fq = { q=>$1, a=>[] }; next }
    if ($cur->{kind} eq 'faq' && $fq) { push @{$fq->{a}}, $l; next }
    if ($cur->{kind} eq 'answer' && !$p->{answer}) { $p->{answer} = plain_md($l) }
    my $cls = $cur->{kind} eq 'answer' ? ' class="lead"' : '';
    $cur->{html} .= "<p$cls>" . inline($l) . "</p>\n";
  }
  $flush_list->(); $flush_table->(); $flush_q->(); push @sec, $cur if $cur;
  die "$p->{file}: '## 한 줄 답변' 구역 없음" unless $p->{answer};
  $p->{sections} = \@sec;
  $p->{faq} = [ map { @{$_->{faq}} } @sec ];
  my $plain = strip(join ' ', map { $_->{html} } @sec);
  (my $nospace = $plain) =~ s/\s+//g;
  $p->{chars} = length $nospace;
  $p->{minutes} = ceil($p->{chars} / 500); $p->{minutes} = 3 if $p->{minutes} < 3;
  $p->{url} = "$BASE/posts/$p->{slug}.html";
  $p->{md_url} = "$BASE/posts/$p->{slug}.md";
  $p->{og} = $p->{cover} && -f "posts/$p->{cover}" ? "$BASE/posts/$p->{cover}" : -f "og/$p->{slug}.png" ? "$BASE/og/$p->{slug}.png" : "$BASE/og/default.png";
  $p->{md} = "# $title\n\n_출처: $p->{url} · 게시 $p->{date} · ${ORG}_\n\n" . join("\n", @body) . "\n\n---\n**문의** ${ORG}(TISKA) · 본사 서울 성동구 성수동 · 자체 공장 서울 중랑구\n전화 02-930-8000 · 이메일 $EMAIL · 홈페이지 $ORG_URL · 소량 제작 https://nadomaker.com\n";
  return $p;
}

# ---------- 레이아웃 ----------
sub nav_html {
  my ($r, $active) = @_;
  my @items = (['index.html','가이드','home'], ['faq.html','자주 묻는 질문','faq'], ['about.html','회사 소개','about']);
  my $n = join '', map { my $a = $_->[2] eq $active ? ' aria-current="page"' : ''; qq{<a href="$r$_->[0]"$a>$_->[1]</a>} } @items;
  return qq{<header class="site"><div class="wrap"><a class="brand" href="${r}index.html">티스카 <span>굿즈 제작 가이드</span></a><nav aria-label="주 메뉴">$n<a href="$ORG_URL" rel="noopener">tiska.kr</a></nav></div></header>};
}
sub footer_html {
  my ($r) = @_;
  return qq{<footer class="site"><div class="wrap"><p><strong>$ORG</strong> · 굿즈·프로모션 상품 주문 제작(OEM/ODM) · 사업자등록번호 275-88-02236 · 대표 오의미</p><p>본사 서울특별시 성동구 아차산로17길 48, 성수 SKV1센터1 1515호 · 자체 공장 서울 중랑구 · 생산 네트워크 중국 광저우·이우</p><p>전화 <a href="tel:+82-2-930-8000">02-930-8000</a> · 이메일 <a href="mailto:$EMAIL">$EMAIL</a> · <a href="$ORG_URL">tiska.kr</a> · 소량·빠른 제작 <a href="https://nadomaker.com">nadomaker.com</a> · <a href="https://www.instagram.com/tiska_office" rel="noopener">Instagram</a> · <a href="https://blog.naver.com/ttiska" rel="noopener">네이버 블로그</a></p><p>모든 숫자는 tiska.kr 공개 정보 기준($FACT_DATE_KO). · <a href="${r}llms.txt">llms.txt</a> · <a href="${r}rss.xml">RSS</a> · <a href="${r}sitemap.xml">사이트맵</a> · © 2026 $ORG</p></div></footer>};
}
sub layout {
  my (%a) = @_;
  my $r = $a{rel};
  my $title = esc($a{title}); my $desc = esc($a{desc});
  my $og_type = $a{type} // 'website';
  my $extra = $a{extra_head} // '';
  my $kw = $a{keywords} ? qq{\n<meta name="keywords" content="} . esc($a{keywords}) . qq{">} : '';
  my $robots = 'index,follow,max-snippet:-1,max-image-preview:large';
  my $css_tag = qq{<link rel="stylesheet" href="${r}style.css">};
  my $canon  = qq{\n<link rel="canonical" href="$a{canonical}">};
  my $ogurl  = qq{\n<meta property="og:url" content="$a{canonical}">};
  return <<"HTML";
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<meta name="description" content="$desc">$kw
<meta name="robots" content="$robots">
<meta name="author" content="$ORG">$canon
<link rel="alternate" type="application/rss+xml" title="$SITE" href="${r}rss.xml">$extra
<link rel="icon" href="${r}favicon.ico" sizes="32x32">
<link rel="icon" href="${r}favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="${r}apple-touch-icon.png">
<meta property="og:type" content="$og_type">
<meta property="og:site_name" content="$SITE">
<meta property="og:locale" content="ko_KR">
<meta property="og:title" content="$title">
<meta property="og:description" content="$desc">$ogurl
<meta property="og:image" content="$a{og}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
$css_tag
$HEAD_EXTRA<script type="application/ld+json">
$a{jsonld}
</script>
</head>
<body>
<a class="skip" href="#main">본문으로 건너뛰기</a>
@{[ nav_html($r, $a{active} // '') ]}
<main id="main" class="wrap">
$a{body}
</main>
@{[ footer_html($r) ]}
</body>
</html>
HTML
}

sub org_json {
  my ($full) = @_;
  my $s = qq|{"\@type":"Organization","\@id":"$ORG_URL/#organization","name":"$ORG","alternateName":["TISKA","티스카"],"url":"$ORG_URL","logo":{"\@type":"ImageObject","url":"$BASE/logo.png","width":512,"height":512}|;
  if ($full) {
    $s .= qq|,"description":"| . j('굿즈·프로모션 상품 주문 제작(OEM/ODM) 제조사. 콘서트 MD, 팬클럽 키트, 기업 웰컴키트, 골프 기념품을 디자인부터 샘플·양산·납품까지 진행. 서울 중랑구 자체 공장과 중국 광저우·이우 생산 네트워크 운영.') . qq|"|;
    $s .= qq|,"foundingDate":"2022-03-01","taxID":"275-88-02236","telephone":"+82-2-930-8000","email":"$EMAIL"|;
    $s .= qq|,"address":{"\@type":"PostalAddress","streetAddress":"아차산로17길 48, 성수 SKV1센터1 1515호","addressLocality":"성동구","addressRegion":"서울특별시","addressCountry":"KR"}|;
    $s .= qq|,"areaServed":["KR","JP","CN","US","ID"],"knowsAbout":["굿즈 제작","콘서트 MD","웰컴키트","골프 기념품","OEM","ODM","아크릴 키링","에코백","금속 뱃지"]|;
    $s .= qq|,"brand":[{"\@type":"Brand","name":"나도메이커","url":"https://nadomaker.com","sameAs":["https://www.instagram.com/nadomaker"]}]|;
    $s .= qq|,"sameAs":["https://www.instagram.com/tiska_office","https://blog.naver.com/ttiska"]|;
  }
  return $s . '}';
}

sub contact_html {
  return qq{<aside class="contact" aria-label="문의"><h2>견적·문의</h2><p><strong>$ORG(TISKA)</strong> · 본사 서울 성동구 성수동 · 자체 공장 서울 중랑구</p><p>전화 <a href="tel:+82-2-930-8000">02-930-8000</a> · 이메일 <a href="mailto:$EMAIL">$EMAIL</a> · 홈페이지 <a href="$ORG_URL">tiska.kr</a></p><p>소량·빠른 제작은 <a href="https://nadomaker.com">나도메이커 nadomaker.com</a></p></aside>};
}

# ---------- 글 페이지 ----------
sub render_post {
  my ($p) = @_;
  my $r = '../';
  my $sections = join '', map {
    my $cls = $_->{kind} eq 'answer' ? ' class="answer"' : $_->{kind} eq 'faq' ? ' class="faq"' : '';
    qq{<section id="$_->{id}"$cls>\n<h2>} . inline($_->{title}) . qq{</h2>\n$_->{html}</section>\n}
  } @{$p->{sections}};
  my @rel = map { $BYN{$_} } grep { exists $BYN{$_} && $_ ne $p->{n} } @{$p->{links}};
  if (@rel < 3) { for my $q (@NEWEST) { next if $q->{n} eq $p->{n} || grep { $_->{n} eq $q->{n} } @rel; push @rel, $q; last if @rel >= 3 } }
  my $related = qq{<nav class="related" aria-label="함께 읽을 글"><h2>함께 읽을 글</h2><ul>} . join('', map { qq{<li><a href="$_->{slug}.html">} . esc($_->{title}) . qq{</a></li>} } @rel) . qq{</ul></nav>};
  my $faq_json = join ',', map { qq|{"\@type":"Question","name":"| . j($_->{q}) . qq|","acceptedAnswer":{"\@type":"Answer","text":"| . j(plain_md(join ' ', @{$_->{a}})) . qq|"}}| } @{$p->{faq}};
  my $kw = join ', ', @{$p->{queries}};
  my $jsonld = qq|{"\@context":"https://schema.org","\@graph":[|
    . qq|{"\@type":"BlogPosting","\@id":"$p->{url}#article","headline":"| . j($p->{title}) . qq|","description":"| . j($p->{desc}) . qq|","inLanguage":"ko-KR","url":"$p->{url}","mainEntityOfPage":{"\@type":"WebPage","\@id":"$p->{url}"},"datePublished":"$p->{iso}","dateModified":"$p->{iso}","author":{"\@id":"$ORG_URL/#organization"},"publisher":{"\@id":"$ORG_URL/#organization"},"image":"$p->{og}","keywords":"| . j($kw) . qq|","articleSection":"굿즈 제작 가이드","wordCount":$p->{chars},"isPartOf":{"\@type":"Blog","\@id":"$BASE/#blog","name":"$SITE"},"isAccessibleForFree":true,"encoding":{"\@type":"MediaObject","contentUrl":"$p->{md_url}","encodingFormat":"text/markdown"},"abstract":"| . j($p->{answer}) . qq|"},|
    . org_json(0) . ','
    . qq|{"\@type":"FAQPage","\@id":"$p->{url}#faq","mainEntity":[$faq_json]},|
    . qq|{"\@type":"BreadcrumbList","itemListElement":[{"\@type":"ListItem","position":1,"name":"홈","item":"$BASE/"},{"\@type":"ListItem","position":2,"name":"제작 가이드","item":"$BASE/index.html#posts"},{"\@type":"ListItem","position":3,"name":"| . j($p->{short}) . qq|","item":"$p->{url}"}]}|
    . qq|]}|;
  my $body = qq{<article>
<nav class="crumb" aria-label="현재 위치"><a href="${r}index.html">홈</a> › <a href="${r}index.html#posts">제작 가이드</a> › <span>} . esc($p->{short}) . qq{</span></nav>
<h1>} . esc($p->{title}) . qq{</h1>
<p class="meta"><time datetime="$p->{date}">$p->{date_ko}</time> · 글 $ORG · 읽는 시간 약 $p->{minutes}분 · 독자: } . esc($p->{reader}) . qq{</p>
$sections
} . contact_html() . qq{
$related
<p class="md-link">이 글의 <a href="$p->{slug}.md" type="text/markdown">마크다운(.md) 원문</a>을 내려받아 AI 도구나 문서에 그대로 쓸 수 있습니다. 숫자 출처: tiska.kr 공개 정보($FACT_DATE_KO).</p>
</article>};
  my $html = layout(title=>"$p->{title} | $SITE", desc=>$p->{desc}, canonical=>$p->{url}, og=>$p->{og}, type=>'article', rel=>$r, body=>$body, jsonld=>$jsonld, keywords=>$kw, active=>'post',
    extra_head=>qq{\n<link rel="alternate" type="text/markdown" href="$p->{slug}.md">\n<meta property="article:published_time" content="$p->{iso}">\n<meta property="article:modified_time" content="$p->{iso}">\n<meta property="article:author" content="$ORG_URL">});
  spit("posts/$p->{slug}.html", $html);
  spit("posts/$p->{slug}.md", $p->{md});
}

# ---------- 홈 ----------
sub render_index {
  my $r = './';
  my $n = scalar @POSTS;
  my $ncase = scalar grep { $_->{kind} eq 'case' } @POSTS;
  my $nguide = $n - $ncase;
  my $hcount = "제작 가이드 ${nguide}편" . ($ncase ? " · 제작 사례 ${ncase}편" : "");
  my $list = join '', map {
    my $label = $_->{kind} eq 'case' ? '제작 사례' : "GUIDE $_->{n}";
    qq{<li><div class="num">$label · <time datetime="$_->{date}">$_->{date_ko}</time></div><h3><a href="posts/$_->{slug}.html">} . esc($_->{title}) . qq{</a></h3><p>} . esc($_->{answer}) . qq{</p><div class="for">독자: } . esc($_->{reader}) . qq{ · 약 $_->{minutes}분 · <a href="posts/$_->{slug}.md">.md</a></div></li>}
  } @NEWEST;
  my $body = qq{<section class="hero">
<h1>$SITE</h1>
<p class="tag">$TAGLINE</p>
<p>이 가이드는 굿즈·프로모션 상품 주문 제작(OEM/ODM) 제조사 <a href="$ORG_URL">$ORG</a>가 직접 씁니다. 총무·마케팅·HR·엔터테인먼트 MD 담당자가 제작을 맡기기 전에 묻는 질문에, 품목별 최소 수량·샘플·양산 기간 같은 숫자로 답합니다. 모든 숫자는 tiska.kr 공개 정보 기준($FACT_DATE_KO)이며 글마다 마크다운 원문을 함께 제공합니다.</p>
<p class="note"><strong>주문 안내(2026년 11월 기준)</strong> 티스카의 메인 발주는 500개부터 진행합니다. 500개 미만의 소량이 필요하시면 자체 소량 제작 쇼핑몰 <a href="https://nadomaker.com">나도메이커</a>를 이용해 주세요.</p>
<div class="stats" aria-label="핵심 숫자">
<div class="stat"><b>메인 발주 500개부터</b><span>모든 품목군 공통 · 500개 미만 소량은 나도메이커</span></div>
<div class="stat"><b>샘플 1일~2주</b><span>양산 7~20일 · 승인 샘플 기준 생산</span></div>
<div class="stat"><b>공개 사례 167건</b><span>고객사 42곳 · 골프·스포츠 82건 · 엔터테인먼트 55건</span></div>
</div>
<p><a class="cta" href="posts/goods-moq-by-item.html">품목별 최소 수량 표 먼저 보기</a> &nbsp; <a href="faq.html">자주 묻는 질문</a></p>
</section>
<section id="posts">
<h2>$hcount <small>(최신 글부터)</small></h2>
<ul class="posts">$list</ul>
</section>
<section id="how">
<h2>이 가이드를 읽는 법</h2>
<p class="note">각 글은 ① 한 줄 답변(숫자 포함) → ② 표와 절차 → ③ 자주 묻는 질문 3개 → ④ 문의 순서로 같은 구조입니다. 기간은 '디자인 확정 시점부터'의 표준 소요 기간이고, 정확한 최소 수량과 단가는 도안 복잡도·가공 방식에 따라 견적 단계에서 확정됩니다. AI 도구에 넣어 요약하거나 비교하려면 <a href="llms.txt">llms.txt</a>와 <a href="llms-full.txt">llms-full.txt</a>(전체 글 전문)를 사용하세요.</p>
</section>
} . contact_html();
  my $posts_json = join ',', map { qq|{"\@type":"BlogPosting","\@id":"$_->{url}#article","headline":"| . j($_->{title}) . qq|","url":"$_->{url}","datePublished":"$_->{iso}","author":{"\@id":"$ORG_URL/#organization"}}| } @NEWEST;
  my $jsonld = qq|{"\@context":"https://schema.org","\@graph":[{"\@type":"WebSite","\@id":"$BASE/#website","url":"$BASE/","name":"$SITE","description":"| . j($SITE_DESC) . qq|","inLanguage":"ko-KR","publisher":{"\@id":"$ORG_URL/#organization"}},| . org_json(1) . qq|,{"\@type":"Blog","\@id":"$BASE/#blog","url":"$BASE/","name":"$SITE","description":"| . j($TAGLINE) . qq|","inLanguage":"ko-KR","publisher":{"\@id":"$ORG_URL/#organization"},"blogPost":[$posts_json]}]}|;
  spit('index.html', layout(title=>"$SITE | 굿즈·MD 주문 제작 최소 수량·기간·비용 안내", desc=>$SITE_DESC, canonical=>"$BASE/", og=>"$BASE/og/default.png", rel=>$r, body=>$body, jsonld=>$jsonld, active=>'home', keywords=>'굿즈 제작, 기업 굿즈, 콘서트 MD 제작, 웰컴키트 제작, 골프 기념품 제작, 굿즈 최소 수량, OEM ODM 굿즈'));
}

# ---------- RSS / llms / OG 제목 ----------
sub write_feeds {
  my $items = '';
  for my $p (@NEWEST) {
    $items .= "<item>\n<title>" . esc($p->{title}) . "</title>\n<link>$p->{url}</link>\n<guid isPermaLink=\"true\">$p->{url}</guid>\n<pubDate>$p->{rfc}</pubDate>\n<description>" . esc($p->{answer}) . "</description>\n</item>\n";
  }
  my $last = $NEWEST[0]{rfc};
  spit('rss.xml', qq{<?xml version="1.0" encoding="UTF-8"?>\n<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">\n<channel>\n<title>} . esc($SITE) . qq{</title>\n<link>$BASE/</link>\n<atom:link href="$BASE/rss.xml" rel="self" type="application/rss+xml"/>\n<description>} . esc($SITE_DESC) . qq{</description>\n<language>ko</language>\n<lastBuildDate>$last</lastBuildDate>\n$items</channel>\n</rss>\n});

  # llms.txt — "## 가이드 글(마크다운 원문)" 구역만 교체(나머지 구역은 _build/build.pl 이 관리)
  my @guides = ("## 가이드 글(마크다운 원문)", map { ($_->{kind} eq 'case' ? '- [제작 사례] ' : '- ') . "[$_->{title}]($_->{md_url}) ($_->{date}): $_->{answer}" } @NEWEST);
  my @ll = split /\r?\n/, slurp('llms.txt');
  my ($hi) = grep { $ll[$_] =~ /^## 가이드 글/ } 0..$#ll;
  die "llms.txt: '## 가이드 글' 구역을 찾지 못함" unless defined $hi;
  my $ei = $hi + 1;
  $ei++ while $ei <= $#ll && $ll[$ei] !~ /^(## |<!--)/;   # 다음 구역(## 또는 <!-- 표시) 직전까지
  $ei-- while $ei - 1 > $hi && $ll[$ei - 1] =~ /^\s*$/;    # 구역 끝의 빈 줄은 남겨 둔다
  splice @ll, $hi, $ei - $hi, @guides;
  spit('llms.txt', join("\n", @ll) . "\n");

  # llms-full.txt — 가이드 전문을 다시 쓰고, 기존 Q&A 구역(<!-- qa:start --> … <!-- qa:end -->)은 그대로 둔다
  my $old = -f 'llms-full.txt' ? slurp('llms-full.txt') : '';
  my ($qa) = $old =~ /(<!-- qa:start -->.*?<!-- qa:end -->)/s;
  my $full = "# $SITE — 전체 글 전문\n\n$SITE_DESC\n운영: $ORG · $ORG_URL · 숫자 기준일 $FACT_DATE · 글 " . scalar(@POSTS) . "편(최신 글부터)\n\n" . join("\n\n---\n\n", map { $_->{md} } @NEWEST);
  $full .= "\n\n---\n\n$qa\n" if $qa;
  spit('llms-full.txt', $full);

  # OG 제목 목록(이미지 생성기용) — og/{slug}.png 가 없는 글은 og/default.png 를 씀
  spit('og/_titles.tsv', join('', map { "$_->{slug}\t$_->{title}\n" } @POSTS) . "default\t$TAGLINE\nfaq\t굿즈 제작, 자주 묻는 질문\n");
}

# ---------- 실행 ----------
make_path('posts', 'og');
parse_post($_) for @POSTS;
render_post($_) for @POSTS;
render_index();
write_feeds();
spit('_build/.last_build_chars.tsv', join('', map { "$_->{slug}\t$_->{chars}\t$_->{kind}\n" } @POSTS));   # publish.sh 분량 검사용(슬러그, 글자 수, 종류)
printf "posts_build 완료: 글 %d편 (최신: %s %s)\n", scalar(@POSTS), $NEWEST[0]{date}, $NEWEST[0]{slug};
printf "  %s  %s  %s %s  %d자 %d분  FAQ %d  OG %s\n", $_->{n}, $_->{slug}, $_->{date}, $_->{time}, $_->{chars}, $_->{minutes}, scalar(@{$_->{faq}}), ($_->{og} =~ /default/ ? 'default' : 'own') for @NEWEST;
