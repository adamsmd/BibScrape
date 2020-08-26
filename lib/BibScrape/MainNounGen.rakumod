unit module BibScrape::MainNounGen;

use variables :D;

use BibScrape::Spell;

enum Stage <stage1 stage2 stage3>;

# cat <(sort cap-aspell.txt | uniq -c) <(sort cap-ispell.txt | uniq -c) <(sort cap-hunspell.txt | uniq -c) <(sort cap-enchant.txt | uniq -c)|sort -n|less
# cat <(sort cap-aspell.txt | uniq -c) <(sort cap-ispell.txt | uniq -c) <(sort cap-hunspell.txt | uniq -c) <(sort cap-enchant.txt | uniq -c)|sort -n >cap-counts.txt

# bin/bibscrape-noungen stage1 dblp/dblp.xml 'ispell -a' >ispell.txt
# bin/bibscrape-noungen stage1 dblp/dblp.xml 'aspell -a' >aspell.txt
# bin/bibscrape-noungen stage1 dblp/dblp.xml 'hunspell -a' >hunspell.txt
# bin/bibscrape-noungen stage1 dblp/dblp.xml 'enscript -a' >enchant.txt
#
# bin/bibscrape-noungen stage2 <(cat {ispell,aspell,hunspell,enchant}.txt) 'ispell -a' 'aspell -a' 'hunspell -a' 'enchant -a' >cap.txt
#
# bin/bibscrape-noungen stage3 dblp/dblp.xml ispell aspell hunspell enchant <cap.txt >annot.txt

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
            $spell.close;
            $spell = BibScrape::Spell::Spell.new(:$cmd);
          }
          $count++;

          my Str:D @words = $spell.capitalization($line);

          @words.map({%words{$_}++});
        }

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
          if $count % 1_000 == 0 { $*ERR.say("Time: {now.DateTime} Lines read: $count"); }
          $count++;
          if $0.Str.Int > 1 {
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
        if $count % 500 == 0 { $*ERR.say("Time: {now.DateTime} Words processed: $count"); }
        $count++;
        for @spell -> BibScrape::Spell::Spell:D $spell {
          my Array:D[Str:D] %sug = $spell.suggest-capitalization($word);
          for %sug.keys -> Str:D $word {
            for %sug{$word} -> Array:D[Str:D] $sugs {
              for $sugs.Array -> Str:D $sug {
                if $sug !~~ /^ <[A..Z]>+ $/ {
                  %word-sug{$word}{$sug} = 1;
                  %word-count{$word} = max(%words{$word}, %word-count{$word} // 0);
                }
              }
            }
          }
        }
      }
      for %word-sug.keys.sort.sort({%word-count{$_}}) -> Str:D $word {
        say %word-count{$word}, " ", $word, " => ", %word-sug{$word}.keys.join(" ");
      }
    }

    when 'stage3' {
      my Str:D @titles;
      my Int:D $count = 0;
      for $file.IO.lines -> Str:D $line is copy {
        next unless $line.starts-with( '<title>' ) and $line.ends-with( '</title>' );
        $line = $line.substr($title-len, *-($title-len + 1));

        push @titles, $line;
        if $count % 100_000 == 0 { $*ERR.say("Time: {now.DateTime} Titles read: $count"); }
        $count++;
        #last if $count > 100_000;
      }

      $count = 0;
      for $*IN.lines -> Str:D $line {
        if $count % 1 == 0 { $*ERR.say("Time: {now.DateTime} Words processed: $count"); }
        $count++;
        $line ~~ /^ (\d+) ' ' (.*) ' => ' (<-[\ ]>+)+ % ' ' $/;
        my Str:D $word = $1.Str;
        say $line;
        say '';
        my Int:D $matches = 0;
        for @titles -> Str:D $title is copy {
          if $title.lc.contains($word) and $title ~~ m:i/ <|w> "$word" <|w> / {
            $title ~~ s:i:g/ ("$word") /----$0----/;
            say $title;
            $matches++;
          }
          last if $matches > 100;
        }
        say '';
        $*OUT.flush;
      }
    }

    default {
      die;
    }
  }
}
