unit module BibScrape::Spell;

use variables :D;

class Spell {
  has Str:D $!cmd is required;
  has Proc::Async:D $!proc is required;
  has IO::Pipe:D $!out is required;
  has Str:D $.version is required;

  method BUILD(Str:D :$cmd = 'ispell -a' --> Any:U) {
    $!cmd = $cmd;
    # We use UTF8-C8 because ispell sometimes outputs invalid UTF8
    #$!proc = shell $cmd, :enc<utf8-c8>, :in, :out; #, :err;
    # We use Proc::Async to avoid a memory leak (see https://github.com/rakudo/rakudo/issues/3858)
    my @args = Rakudo::Internals.IS-WIN
            ?? (%*ENV<ComSpec>, '/c', $cmd)
            !! ('/bin/sh', '-c', $cmd);
    $!proc = Proc::Async.new(@args, :w, :enc<utf8-c8>);

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
    if $!cmd ~~ /enchant/ and $text !~~ / <[A..Za..z]> / { # Work around for bug in enchant where lines without text don't produce output
      # However, this introduces another bug into .capitalization
      {}
    } else {

      $!proc.say(" $text"); # The space at front prevents interpretation as command
      gather {
        loop {
          given $!out.get {
            when '' { last; }
            when /^ <[*+-]> / { } # Do nothing
            when /^ <[&?]> ' '? (.+) ' ' \d+ ' ' \d+ ':' ' ' (.+?)+ % ', ' $/ {
              take $0.Str => $1.map(*.Str).Array;
            }
            # The ? on ' ' allows us to deal with strings that start with a combining character (TODO: report bug in hunspell and enchant?)
            when /^ '#' ' '? (.+) ' ' \d+ $/ { take $0.Str => [].Array; }
            default { die "Could not parse output for '$text': $_" }
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
