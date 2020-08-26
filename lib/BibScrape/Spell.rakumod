unit module BibScrape::Spell;

use variables :D;

class Spell {
  has Proc::Async:D $!proc is required;
  has IO::Pipe:D $!out is required;
  has Str:D $.version is required;

  method BUILD(Str:D :$prog = 'ispell' --> Any:U) {
    # We use UTF8-C8 because ispell sometimes outputs invalid UTF8
    # TODO: use shell and prog = 'ispell -a'
    #$!proc = run $prog, '-a', :enc<utf8-c8>, :in, :out; #, :err;
    # We use Proc::Async to avoid a memory leak (see https://github.com/rakudo/rakudo/issues/3858)
    $!proc = Proc::Async.new($prog, '-a', :w, :enc<utf8-c8>);

    my $stdout-supply = $!proc.stdout(:bin);
    my $chan = $stdout-supply.Channel;
    $!out = IO::Pipe.new(:proc($!proc), :enc<utf8-c8>,
        :on-read({ (try $chan.receive) // buf8 }),
        :on-close({ }),
        :on-native-descriptor({ await $stdout-supply.native-descriptor }));
    $!proc.start;
    $!version = $!out.get;
    return;
  };

  method check(Str:D $text --> Array:D[Str:D]) {
    self.suggest($text).keys.Array;
  }

  method suggest(Str:D $text --> Hash:D[Array:D[Str:D]]) {
    if $text !~~ / <[A..Za..z]> / { # Work around for bug in enchant
      {}
    } else {

      $!proc.say(" $text"); # The space at front prevents interpretation as command
      gather {
        loop {
          given $!out.get {
            when '' { last; }
            when /^ <[*+-]> / { } # Do nothing
            when /^ <[&?]> ' ' (.+) ' ' \d+ ' ' \d+ ':' ' ' (.+?)+ % ', ' $/ {
              take $0.Str => $1.map(*.Str).Array;
            }
            when /^ '#' ' ' (.+) ' ' \d+ $/ { take $0.Str => [].Array; }
            default { die "Could not parse ispell output for '$text': $_" }
          }
        }
      }.Hash
    }
  }
  method capitalization(Str:D $text --> Array:D[Str:D]) {
    my Str:D @words = self.check($text.lc);
    # Ispell ignores case when upper case
    @words.grep({ !self.check($_.uc) }).Array;
  }
  method suggest-capitalization(Str:D $text --> Hash:D[Array:D[Str:D]]) {
    my Str:D @words = self.capitalization($text);
    my Array:D[Str:D] %suggest = self.suggest(@words.join(" "));
    %suggest.pairs.map(-> $x {$x.key => $x.value.grep({$x.key.fc eq $_.fc}).Array}).Hash;
  }
  method close(--> Any:U) {
    # $!proc.in.close;
    # $!proc.out.close;
    # $!proc.err.close;
    $!proc.kill;
    $!proc.so;
    return;
  }
  method DESTROY(--> Any:U) { self.close(); }
}

#  grep '^<title>' dblp/dblp.xml | perl -pe 's/^<title>//; s[</title>$][]' | raku -I lib -M BibScrape::Spell -ne 'my $x; my $y; BEGIN { $x = BibScrape::Spell::Spell.new(prog => "aspell"); say $x.version}; my @x = $x.capitalization($_); if $y++ % 1000 == 0 { say "!!!! $y !!!!"; }; if @x { .say for @x }' >cap-aspell.txt
#hunspell
#enchant

#  grep '^<title>' dblp/dblp.xml | perl -pe 's/^<title>//; s[</title>$][]' | raku -I lib -M BibScrape::Spell -ne 'my $x; my $y; BEGIN { $x = BibScrape::Spell::Spell.new(prog => "ispell"); say $x.version}; my @x = $x.capitalization($_); if $y++ % 1000 == 0 { say "!!!! $y !!!!"; }; if @x { .say for @x }' >cap-ispell.txt

# grep '^<title>' dblp/dblp.xml | perl -pe 's/^<title>//; s[</title>$][]' | raku -I lib -M BibScrape::Spell -ne 'my $x; my $y; BEGIN { $x = BibScrape::Spell::Spell.new(prog => "aspell"); say $x.version}; my @x = $x.capitalization($_); if $y++ % 1000 == 0 { say "!!!! $y !!!!"; }; if $y % 10000 == 0 { $x.close; $x = BibScrape::Spell::Spell.new(prog => "aspell"); }; if @x { .say for @x }' >cap-aspell.txt

# grep '^<title>' dblp/dblp.xml | perl -pe 's/^<title>//; s[</title>$][]' | raku -I lib -M BibScrape::Spell -ne 'my $x; my $y; BEGIN { $x = BibScrape::Spell::Spell.new(prog => "hunspell"); say $x.version}; my @x = $x.capitalization($_); if $y++ % 1000 == 0 { say "!!!! $y !!!!"; }; if @x { .say for @x }' >cap-hunspell.txt

# cat <(sort cap-aspell.txt | uniq -c) <(sort cap-ispell.txt | uniq -c) <(sort cap-hunspell.txt | uniq -c) <(sort cap-enchant.txt | uniq -c)|sort -n|less
# cat <(sort cap-aspell.txt | uniq -c) <(sort cap-ispell.txt | uniq -c) <(sort cap-hunspell.txt | uniq -c) <(sort cap-enchant.txt | uniq -c)|sort -n >cap-counts.txt


