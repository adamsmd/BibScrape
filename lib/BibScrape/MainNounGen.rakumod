unit module BibScrape::MainNounGen;

use variables :D;

use HTML::Entity;

use BibScrape::Spell;

enum Stage <stage1 stage2 stage3>;

# bin/bibscrape-noungen stage1 dblp/dblp.xml 'ispell -a' >nouns-stage1-ispell.txt
# bin/bibscrape-noungen stage1 dblp/dblp.xml 'aspell -a' >nouns-stage1-aspell.txt
# bin/bibscrape-noungen stage1 dblp/dblp.xml 'hunspell -a' >nouns-stage1-hunspell.txt
# bin/bibscrape-noungen stage1 dblp/dblp.xml 'enchant -a' >nouns-stage1-enchant.txt
# ~40 hours
#
# bin/bibscrape-noungen stage2 <(cat nouns-stage1-*.txt) 'ispell -a' 'aspell -a' 'hunspell -a' 'enchant -a' >nouns-stage-2.txt
# ~9 min
#
# bin/bibscrape-noungen stage3 nouns-stage2.txt <dblp/dblp.xml >nouns-stage3.txt
# ~2min
#
# bin/bibscrape-noungen stage4 nouns-stage3.txt >nouns-stage4.txt
# ~6min
#
# TODO: All words that are hyphenated with personal names?
#
# 1 asimov’s
# 1 devanāgari
# 1 sā
# 1 sī
# 1 sōto
# 1 ēlvis
# 2 čr
# 2 œ
#
# "tesla" (unit)

sub MAIN(Str:D $mode, Str:D $file, Str:D @cmds) is export {
  constant $title-len = '<title>'.chars.Int;

  given $mode {
    when 'stage1' {
      for @cmds -> Str:D $cmd {
        my BibScrape::Spell::Spell:D $spell = BibScrape::Spell::Spell.new(:$cmd);

        my Int:D %words;
        my Int:D $count = 0;

        for $file.IO.lines -> Str:D $line is copy {
          next unless $line.starts-with( '<title>' ) and $line.ends-with( '</title>' );
          $line = $line.substr($title-len, *-($title-len + 1));

          if $count % 10_000 == 0 { $*ERR.say("Time: {now.DateTime} Lines: $count"); }
          if $count % 100_000 == 0 {
            # Prevent memory leaks in some spell checkers
            $spell.close;
            $spell = BibScrape::Spell::Spell.new(:$cmd);
          }
          $count++;

          $line = decode-entities($line);
          my Str:D @words = $spell.capitalization($line);
          #my Str:D @words2 = $spell.check($line);
          #if @words2 { $*ERR.say(@words2); }

          @words.map({%words{$_}++});
        }
        # TODO: words that do not spell at all

        say $spell.version;
        for %words.keys.sort.sort({%words{$_}}) -> Str:D $word {
          say "{%words{$word}} $word";
        }

        $spell.close;
      }
    }

    when 'stage2' {
      my Int:D %words;
      my Int:D $count = 0;
      for $file.IO.lines {
        if / \s* (\d+) \s+ (.*) / {
          if $0.Str.Int > 1 { # Ignore words occuring only once
            if $count % 1_000 == 0 { $*ERR.say("Time: {now.DateTime} Lines read: $count"); }
            $count++;
            %words{$1.Str} = max($0.Str.Int, %words{$1.Str} // 0);
          }
        }
      }

      my Hash:D[Int:D] %word-sug;
      my Int:D %word-count;
      my BibScrape::Spell::Spell:D @spell =
        @cmds.map({ BibScrape::Spell::Spell.new(:cmd($_)) });
      $count = 0;
      for %words.keys -> Str:D $word {
        if $count % 100 == 0 { $*ERR.say("Time: {now.DateTime} Words processed: $count"); }
        $count++;
        for @spell -> BibScrape::Spell::Spell:D $spell {
          my Array:D[Str:D] %sug = $spell.suggest-capitalization($word);
          for %sug.keys -> Str:D $sug1 { # TODO: rename
            for %sug{$sug1} -> Array:D[Str:D] $sugs {
              for $sugs.Array -> Str:D $sug {
                #if $sug !~~ /^ <[A..Z]>+ $/ { # Omit acronyms
                  %word-sug{$word}{$sug} = 1;
                  %word-count{$word} = max(%words{$word}, %word-count{$word} // 0);
                #}
              }
            }
          }
        }
      }
      for %word-sug.keys.sort.sort({%word-count{$_}}).List.reverse -> Str:D $word {
        say %word-count{$word}, " ", $word, " => ", %word-sug{$word}.keys.join(" ");
      }
    }

    when 'stage3' {
      my Int:D $count = 0;
      my Array:D[Str:D] %words;
      my Str:D %word-info;
      for $file.IO.lines -> Str:D $line {
        if $count % 1_000 == 0 { $*ERR.say("Time: {now.DateTime} Words processed: $count"); }
        $count++;
        $line ~~ /^ (\d+) ' ' (.*) ' => ' (<-[\ ]>+)+ % ' ' $/;
        my Str:D $word = $1.Str;
        $word ~~ /^ (.*?) » /;
        %words{$0.Str}.push($word);
        %word-info{$word} = $line;
      }

      $count = 0;
      my Bool:D $skip = False;
      for $*IN.lines -> Str:D $line is copy {
        if $line.contains( '</proceedings' ) or $line.contains( '</book' ) { $skip = False }
        if $line.contains( '<proceedings ' ) or $line.contains( '<book ' ) { $skip = True }
        next if $skip;
        next unless $line.starts-with( '<title>' ) and $line.ends-with( '</title>' );
        $line = $line.substr($title-len, *-($title-len + 1));

        $line = decode-entities($line);

        if $count % 10_000 == 0 { $*OUT.flush; $*ERR.say("Time: {now.DateTime} Titles processed: $count"); }
        $count++;

        #$*ERR.say("line: $line") if $line ~~ /^ :i bayesian /;
        for $line ~~ m:g/ « (.*?) » / -> Match:D $match {
          my Int:D $pos = $match.from;
          #$*ERR.say($match[0]);
          #$*ERR.say(%words{$match[0].Str}.raku);
          #$*ERR.say((@(%words{$match[0].Str} // Array.new())).raku);
          #$*ERR.say("match: {$match.pos} {$line.substr($pos, 3).lc}") if $line ~~ /^ :i bayesian /;
          #$*ERR.say("") if $line ~~ /^ :i bayesian /;
          #$*ERR.say($line) if $match.Str ~~ /^ :i bayesian /;
          #$*ERR.say($match) if $match.Str ~~ /^ :i bayesian /;
          #$*ERR.say($match.pos) if $match.Str ~~ /^ :i bayesian /;
          my @words = @(%words{$match[0].Str.lc} // Array.new());
          #$*ERR.say("match: {$match.Str} {$match.pos} {@words.join(':')}") if $line ~~ /^ :i bayesian /;
          #$*ERR.say(@words);
          #$*ERR.say(@words.join(":"));
          #$*ERR.say("name: ", %words{$line.substr($pos, 3).lc}.^name);
            # |(%words{$line.substr($pos, 2).lc} // Array.new()),
            # |(%words{$line.substr($pos, 3).lc} // Array.new()),
            # |(%words{$line.substr($pos, 4).lc} // Array.new());
          #$*ERR.say("foo: {%words{$line.substr($pos, 3).lc}.List.join(':')}");
          # TODO: fix this List vs Array mess
          #my $words = (%words{$line.substr($pos, 2).lc} // (), %words{$line.substr($pos, 3.lc)} // ()).flat.Array;
          #$words = $words.map({$_.List}).flat;
          #$*ERR.say("words: {@words.Int} {@words.join(':')}") if $line ~~ /^ :i bayesian /;
          for @words -> Str:D $word {
            #$*ERR.say("word $word") if $word.Str ~~ /^ :i bayesian /;
            #$*ERR.say("word-info $pos $word :: $line") if $word.Str ~~ /^ :i bayesian /;
            #if $line.substr-eq($word, $pos, :i) and $line ~~ m:pos($pos + $word.chars)/ » / {
            if $line ~~ m:i:pos($pos)/ $word » / {
              #$*ERR.say("word-info+") if $word.Str ~~ /^ :i bayesian /;
              #$*ERR.say("word-info %word-info{$word}") if $word.Str ~~ /^ :i bayesian /;
              say "%word-info{$word} => $line";
            }
          }
        }
      }
    }

    # when 'stage3' {
    #   my Str:D @titles;
    #   my Int:D $count = 0;
    #   my Bool:D $skip = False;
    #   for $file.IO.lines -> Str:D $line is copy {
    #     if $line.contains( '</proceedings' ) or $line.contains( '</book' ) { $skip = False }
    #     if $line.contains( '<proceedings ' ) or $line.contains( '<book ' ) { $skip = True }
    #     next if $skip;
    #     next unless $line.starts-with( '<title>' ) and $line.ends-with( '</title>' );
    #     $line = $line.substr($title-len, *-($title-len + 1));

    #     $line = decode-entities($line);
    #     push @titles, $line;
    #     if $count % 100_000 == 0 { $*ERR.say("Time: {now.DateTime} Titles read: $count"); }
    #     $count++;
    #     #last if $count > 770_000;
    #     # TODO: check decoded words
    #   }

    #   $count = 0;
    #   for $*IN.lines -> Str:D $line {
    #     if $count % 1 == 0 { $*ERR.say("Time: {now.DateTime} Words processed: $count"); }
    #     $count++;
    #     $line ~~ /^ (\d+) ' ' (.*) ' => ' (<-[\ ]>+)+ % ' ' $/;
    #     my Str:D $word = $1.Str;
    #     say $line;
    #     say '';
    #     for @titles -> Str:D $title is copy {
    #       # TODO: build regex of all words?
    #       if $title.contains($word, :i) {
    #         say $title;
    #       }
    #     }
    #     say '';
    #     $*OUT.flush;
    #   }
    # }

    when 'stage4' {
      my Array:D[Str:D] %titles;
      my Int:D $count = 0;
      my Bool:D $skip = False;
      for $file.IO.lines -> Str:D $line {
        if $count % 10_000 == 0 { $*ERR.say("Time: {now.DateTime} Words processed: $count"); }
        $count++;
        $line ~~ /^ (.* ' => ' .*) ' => ' (.*) $/;
        %titles{$0.Str}.push($1.Str);
      }

      $count = 0;
      for %titles.keys.sort.reverse.sort({$_.split(" ").head.Int}).reverse -> Str:D $key {
        $key ~~ /^ (\d+) ' ' (.*) ' => ' (<-[\ ]>+)+ % ' ' $/;
        my Int:D $number = $0.Int;
        my Str:D $word = $1.Str;
        my Str:D @sug = $2.List».Str;
        # TODO: Monti-Carlo as tc2
        # TODO: TCP's
        # TODO: McCarty (as givn by spell checker)
        say $key;
        print "Titles: ", %titles{$key}.Int;
        my Str:D $word-uc = $word.uc;
        my Str:D $word-tc = $word.tc;
        my Int:D $lc = 0;
        my Int:D $uc = 0;
        my Int:D $tc = 0;
        my Int:D $ot = 0;
        my Int:D %sug;
        TITLE:
        for @(%titles{$key}) -> Str:D $title {
          #say "TT: $title $word $word-uc $word-tc";
          given $title {
            when / «$word» / { $lc++; }
            when / «$word-uc» / { $uc++; }
            when / «$word-tc» / { $tc++; }
            default {
              for @sug -> Str:D $sug {
                if $sug ~~ /^ :i $word $/ {
                  unless $sug ~~ $word | $word.uc | $word.tc {
                    if $title ~~ / «$sug» / {
                      %sug{$sug}++;
                      next TITLE;
                    }
                  }
                }
              }
              $ot++;
            }
          }
        }
        print " LC: $lc UC: $uc TC: $tc";
        for %sug.keys -> Str:D $sug {
          print " SU $sug: ", %sug{$sug};
          unless $sug ~~ / . <upper> / { die "Non-acronym suggestion: $sug"; }
        }
        say " OT: $ot";
        say '';

        #say "Lower: ", %titles{$key}; ____ xx ____
        #say "Titles: ", %titles{$key}.Int;

        for %titles{$key}.pick(100) -> Str:D $title is copy {
          $title ~~ s:i:g/ <wb> ($word) <wb> /____$0____/;
          $title ~~ s:g/ '____' ($word) '____' /----$0----/;
          $title ~~ s:g/ '____' ($word-uc) '____' /....$0..../;
          $title ~~ s:g/ '____' ($word-tc) '____' /~~~~$0~~~~/;
          say $title;
        }
      
        say '';
        say '';
      }
      #   my Str:D $out = '';
      #   my Int:D $matches = 0;
      #   my Int:D $upper-case = 0;
      #   my Int:D $lower-case = 0;
      #   my Int:D $title-case = 0;
      #   for @titles -> Str:D $title is copy {
      #     if $title.contains($word, :i) { # Fast fail for performance
      #       if $title ~~ s:i:g/ <wb> ($word) <wb> /____$0____/ {
      #         $matches++;
      #         $upper-case++ if $title ~~ s:g/ '____' ($word-uc) '____' /....$0..../;
      #         $lower-case++ if $title ~~ s:g/ '____' ($word) '____' /----$0----/;
      #         $title-case++ if $title ~~ s:g/ '____' ($word-tc) '____' /~~~~$0~~~~/;
      #         $out ~= $title ~ "\n";
      #       }
      #     }
      #     last if $matches >= 100;
      #   }
      #   # TODO: Sort $out by cases
      #   # TODO: "Acrynom" (spell check suggestions?) "Other Case"
      #   say "Matches: $matches Upper Case: $upper-case Lower Case: $lower-case Title Case: $title-case";
      #   say '';
      #   print $out;
      #   say '';
      #   $*OUT.flush;
      # }
    }

    # when 'stage4' {
    #   my Str:D @titles;
    #   my Int:D $count = 0;
    #   my Bool:D $skip = False;
    #   for $file.IO.lines -> Str:D $line is copy {
    #     if $line.contains( '</proceedings' ) or $line.contains( '</book' ) { $skip = False }
    #     if $line.contains( '<proceedings ' ) or $line.contains( '<book ' ) { $skip = True }
    #     next if $skip;
    #     next unless $line.starts-with( '<title>' ) and $line.ends-with( '</title>' );
    #     $line = $line.substr($title-len, *-($title-len + 1));

    #     $line = decode-entities($line);
    #     push @titles, $line;
    #     if $count % 100_000 == 0 { $*ERR.say("Time: {now.DateTime} Titles read: $count"); }
    #     $count++;
    #     #last if $count > 770_000;
    #     # TODO: check decoded words
    #   }

    #   $count = 0;
    #   for $*IN.lines -> Str:D $line {
    #     if $count % 1 == 0 { $*ERR.say("Time: {now.DateTime} Words processed: $count"); }
    #     $count++;
    #     $line ~~ /^ (\d+) ' ' (.*) ' => ' (<-[\ ]>+)+ % ' ' $/;
    #     my Str:D $word = $1.Str;
    #     my Str:D $word-uc = $word.uc;
    #     my Str:D $word-tc = $word.tc;
    #     # TODO: Monti-Carlo as tc2
    #     # TODO: TCP's
    #     # TODO: McCarty (as givn by spell checker)
    #     say $line;
    #     my Str:D $out = '';
    #     my Int:D $matches = 0;
    #     my Int:D $upper-case = 0;
    #     my Int:D $lower-case = 0;
    #     my Int:D $title-case = 0;
    #     for @titles -> Str:D $title is copy {
    #       if $title.contains($word, :i) { # Fast fail for performance
    #         if $title ~~ s:i:g/ <wb> ($word) <wb> /____$0____/ {
    #           $matches++;
    #           $upper-case++ if $title ~~ s:g/ '____' ($word-uc) '____' /....$0..../;
    #           $lower-case++ if $title ~~ s:g/ '____' ($word) '____' /----$0----/;
    #           $title-case++ if $title ~~ s:g/ '____' ($word-tc) '____' /~~~~$0~~~~/;
    #           $out ~= $title ~ "\n";
    #         }
    #       }
    #       last if $matches >= 100;
    #     }
    #     # TODO: Sort $out by cases
    #     # TODO: "Acrynom" (spell check suggestions?) "Other Case"
    #     say "Matches: $matches Upper Case: $upper-case Lower Case: $lower-case Title Case: $title-case";
    #     say '';
    #     print $out;
    #     say '';
    #     $*OUT.flush;
    #   }
    # }

    default {
      die;
    }
  }
}

sub find(Str:D $line, Str:D $word) {


}