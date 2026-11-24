#!/usr/bin/perl
# 제작 사례 초안 미리보기 — 사장님 확인용 HTML 한 장(사진은 base64로 내장, 파일 하나로 열림)
# 사용:  perl _build/case_preview.pl 출력.html _src/drafts/C01_*.md _src/drafts/C02_*.md ...
#        (저장소 어느 위치에서 실행해도 됨. 사진 경로는 원고의 img/… 를 posts/img/… 로 찾는다)
use strict; use warnings; use utf8;
use open qw(:std :encoding(UTF-8));
use File::Basename qw(dirname basename);
use MIME::Base64 qw(encode_base64);

my $ROOT = dirname(dirname(__FILE__));
chdir $ROOT or die "cannot chdir $ROOT";

my ($out, @files) = @ARGV;
die "사용: perl _build/case_preview.pl 출력.html 원고1.md [원고2.md ...]\n" unless $out && @files;

sub slurp { my $f = shift; open my $fh, '<', $f or die "읽기 실패 $f: $!"; local $/; my $s = <$fh>; close $fh; $s =~ s/^\x{FEFF}//; return $s }
sub esc { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; return $s }
sub inline {
  my $s = esc(shift);
  $s =~ s{\*\*(.+?)\*\*}{<strong>$1</strong>}g;
  $s =~ s{(https?://[^\s<>()"]+)}{<a href="$1" target="_blank" rel="noopener">$1</a>}g;
  return $s;
}
sub img_data {
  my $src = shift;                       # 원고 기준 img/xxx.jpg → posts/img/xxx.jpg
  my $f = "posts/$src";
  return (undef, "사진 파일 없음: $f") unless -f $f;
  open my $fh, '<:raw', $f or return (undef, "읽기 실패 $f");
  local $/; my $bin = <$fh>; close $fh;
  my $mime = $f =~ /\.png$/i ? 'image/png' : $f =~ /\.webp$/i ? 'image/webp' : 'image/jpeg';
  return ("data:$mime;base64," . encode_base64($bin, ''), sprintf('%s · %.0f KB', basename($f), length($bin) / 1024));
}

my @cards; my @toc; my $i = 0;
for my $file (@files) {
  $i++;
  my $md = slurp($file);
  my ($code) = basename($file) =~ /^(C\d+)/; $code //= "초안$i";
  my @lines = split /\r?\n/, $md;
  my $title = ''; my $meta = ''; my $cover = ''; my @notes;
  my $html = ''; my @tbl; my @list; my $in_meta = 0; my $nimg = 0; my $chars = 0; my $body_started = 0;
  my $flush_tbl = sub {
    return unless @tbl;
    my @rows = grep { !/^\|\s*-{2,}/ } @tbl;
    my $h = "<table>";
    for my $k (0 .. $#rows) {
      my @c = map { s/^\s+|\s+$//gr } grep { length } split /\|/, $rows[$k];
      @c = map { s/^\s+|\s+$//gr } split /\|/, substr($rows[$k], 1, length($rows[$k]) - 2) if $rows[$k] =~ /^\|.*\|$/;
      my $tag = $k == 0 ? 'th' : 'td';
      $h .= '<tr>' . join('', map { "<$tag>" . inline($_) . "</$tag>" } @c) . '</tr>';
    }
    $html .= "$h</table>\n"; @tbl = ();
  };
  my $flush_list = sub { return unless @list; $html .= '<ul>' . join('', map { '<li>' . inline($_) . '</li>' } @list) . "</ul>\n"; @list = () };
  for my $l (@lines) {
    if (!$title && $l =~ /^#\s+(.+)/) { $title = $1; next }
    if ($l =~ /^>\s*\*\*발행 메모/) { $in_meta = 1; next }
    if ($in_meta) {
      if ($l =~ /^>\s*-?\s*(.*)$/) { my $m = $1; push @notes, $m if length $m; $meta = $1 if $m =~ /^메타 설명:\s*(.+)/; $cover = $1 if $m =~ /^대표 이미지:\s*(\S+)/; next }
      $in_meta = 0;
    }
    if ($l =~ /^##\s+(.+)/) { $flush_tbl->(); $flush_list->(); $html .= '<h2>' . esc($1) . "</h2>\n"; $body_started = 1; next }
    if ($l =~ /^---\s*$/) { $flush_tbl->(); $flush_list->(); $html .= "<hr>\n"; next }
    if ($l =~ /^!\[([^\]]*)\]\(([^)\s]+)\)\s*$/) {
      $flush_tbl->(); $flush_list->();
      my ($alt, $src) = ($1, $2); $nimg++;
      my ($data, $info) = img_data($src);
      $html .= $data
        ? qq{<figure><img src="$data" alt="} . esc($alt) . qq{"><figcaption>} . esc($alt) . qq{ <small>($info)</small></figcaption></figure>\n}
        : qq{<p class="missing">[사진 누락] } . esc($info) . qq{</p>\n};
      next;
    }
    if ($l =~ /^\|/) { $flush_list->(); push @tbl, $l; next }
    if ($l =~ /^\s*[-*]\s+(.+)/) { $flush_tbl->(); push @list, $1; $chars += length($1 =~ s/\s//gr) if $body_started; next }
    if ($l =~ /^\s*$/) { $flush_tbl->(); $flush_list->(); next }
    $flush_tbl->(); $flush_list->();
    $html .= '<p>' . inline($l) . "</p>\n";
    $chars += length($l =~ s/\s//gr) if $body_started;
  }
  $flush_tbl->(); $flush_list->();
  my ($orig) = $md =~ m{(https://tiska\.kr/board/\S+)};
  my $head = sprintf('%s · 사진 %d장 · 본문 약 %s자(공백 제외, 표 제외)', $code, $nimg, $chars =~ s/(\d)(?=(\d{3})+$)/$1,/gr);
  push @toc, qq{<li><a href="#$code">$code</a> } . esc($title) . qq{</li>};
  push @cards, qq{<article id="$code"><div class="code">$head</div><h1>} . esc($title) . qq{</h1>}
    . ($meta ? qq{<p class="meta"><b>검색 결과에 보이는 설명</b> } . esc($meta) . qq{</p>} : '')
    . ($cover ? qq{<p class="meta"><b>대표(공유) 이미지</b> } . esc($cover) . qq{</p>} : '')
    . ($orig ? qq{<p class="meta"><b>tiska.kr 원본 사례</b> <a href="$orig" target="_blank" rel="noopener">$orig</a></p>} : '')
    . qq{<div class="body">$html</div>}
    . qq{<p class="ask">이 글에 대한 의견: <b>"$code 승인"</b> / <b>"$code 제목 바꿔서 …"</b> / <b>"$code 빼기"</b> 처럼 채팅에 적어 주세요.</p></article>};
}

my $n = scalar @cards;
my $page = qq{<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>제작 사례 글 초안 ${n}편 — 확인 요청</title>
<style>
body{font-family:-apple-system,"Malgun Gothic","Apple SD Gothic Neo",sans-serif;line-height:1.65;color:#1f2937;background:#f3f4f6;margin:0;padding:24px 16px}
.wrap{max-width:860px;margin:0 auto}
.intro{background:#fff;border:1px solid #e5e7eb;border-radius:14px;padding:18px 22px;margin-bottom:22px}
.intro h1{font-size:1.35em;margin:.2em 0 .6em}.intro ol{margin:.4em 0 .4em 1.2em}
article{background:#fff;border:1px solid #e5e7eb;border-radius:14px;padding:22px 26px;margin-bottom:28px}
article h1{font-size:1.45em;line-height:1.35;margin:.3em 0 .6em}
.code{display:inline-block;background:#1e3a8a;color:#fff;font-size:.8em;padding:3px 10px;border-radius:999px}
.meta{font-size:.9em;color:#4b5563;background:#f9fafb;border-left:3px solid #c7d2fe;padding:6px 10px;margin:.3em 0}
.body h2{font-size:1.12em;margin:1.5em 0 .5em;padding-top:.4em;border-top:1px solid #eef0f3}
table{border-collapse:collapse;width:100%;font-size:.93em;margin:.6em 0}
th,td{border:1px solid #e5e7eb;padding:7px 9px;text-align:left;vertical-align:top}th{background:#f9fafb}
figure{margin:1.2em 0}figure img{display:block;max-width:100%;height:auto;border-radius:12px;border:1px solid #e5e7eb}
figcaption{font-size:.85em;color:#6b7280;margin-top:.4em}
.missing{color:#b91c1c;font-weight:600}
.ask{background:#fef3c7;border-radius:10px;padding:10px 14px;font-size:.95em}
a{color:#1d4ed8}
</style></head><body><div class="wrap">
<div class="intro"><h1>제작 사례 글 초안 ${n}편 — 확인 부탁드립니다</h1>
<p>아래 글은 tiska.kr에 공개된 제작 사례 표와 사진만으로 썼습니다. 승인하신 글만 블로그(ohyoumeee-prog.github.io/tiska-guide)에 매일 1편씩 올라갑니다.</p>
<ol>} . join('', @toc) . qq{</ol>
<p>확인 방법: 채팅에 <b>"전부 승인"</b>, <b>"C01·C03만 승인"</b>, <b>"C02는 제목을 ○○로 바꿔서 승인"</b> 처럼 적어 주시면 됩니다. 사진이 마음에 안 드시면 바꿀 사진 번호나 파일을 알려 주세요.</p></div>
} . join("\n", @cards) . qq{
</div></body></html>};

my ($d) = $out =~ m{^(.*)/}; if ($d && !-d $d) { require File::Path; File::Path::make_path($d) }
open my $fh, '>', $out or die "쓰기 실패 $out: $!"; print $fh $page; close $fh;
printf "미리보기 저장: %s (%d편, %.1f MB)\n", $out, $n, (-s $out) / 1048576;
