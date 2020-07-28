unit module BibScrape::Names;

# See:
# - https://github.com/aclements/biblib/blob/master/biblib/algo.py
# - https://maverick.inria.fr/~Xavier.Decoret/resources/xdkbibtex/bibtex_summary.html
# - https://www.ctan.org/tex-archive/info/bibtex/tamethebeast/

# grammar Grammar {
#   token TOP { ^ <names> $ }
#   regex names { <name>* %% [ \s+ 'and' \s+ ] }
#   regex name { <word> }
#   regex word { <balanced>+? }
#   regex balanced { '{' <balanced>* '}' | <-[{}]> }
# }

# sub parse(Str $str) is export {
#   Grammar.parse($str)
# }

sub depths(Str $str --> Array[Int]) {
  my Int @depths;
  my Int $depth = 0;
  for $str.split('', :skip-empty) -> $char {
    push @depths, $depth;
    given $char {
      when '{' { $depth++; pop @depths; push @depths, $depth }
      when '}' { $depth-- }
    }
  }
  @depths;
}

sub depth-split(Str $str, Regex $regex --> Array[Str]) {
  my Int @depths = depths($str);
  my Int @positions = (0,
    ($str ~~ m:g/ $regex /)
      .grep({ !@depths[$_.from] })
      .map({ (.from - 1, .to) }).flat,
    $str.chars).flat;
  my Str @parts = @positions.map(sub ($from, $to) { $str.substr($from..$to) });
  @parts;
}

sub split-name(Str $str --> Array[Str]) is export {
  depth-split($str, rx/ \s* ',' \s* /);
}

sub split-names(Str $str --> Array[Str]) is export {
  depth-split($str, rx/ \s+ 'and' \s+ /);
}

# TODO: note that these are not exactly how BibTeX parses names, but they are good enough for us (because we avoid capitalization distinctions)
# TODO: factor out common code
sub flatten-name(Str $str --> Str) is export {
  my Str @parts = split-name($str.trim);
  do given @parts.elems {
    when 1 { "@parts[0]" }
    when 2 { "@parts[1] @parts[0]" }
    when 3 { "@parts[2] @parts[0] @parts[1]" }
    default { die "Too many commas in name <$str>" }
  }
}

# TODO: note that this may not include the 'von' (but only when in no-comma form)
sub order-name(Str $str --> Str) is export {
  my Str @parts = split-name($str.trim);
  do given @parts.elems {
    when 1 {
      my Str @words = depth-split(@parts[0], rx/ \s+ /);
      @words[*-1] ~ ', ' ~ @words[0..^*-1].join( ' ' )
    }
    when 2 { "@parts[0], @parts[1]" }
    when 3 { "@parts[0], @parts[1], @parts[2]" }
    default { die "Too many commas in name <$str>" }
  }
}

# TODO: note that this may include the 'von' (but not when in no-comma form)
sub last-name(Str $str --> Str) is export {
 my Str @parts = split-name($str.trim);
  do given @parts.elems {
    when 1 {
      my Str @words = depth-split(@parts[0], rx/ \s+ /);
      @words[*-1]
    }
    when 2 { @parts[0] }
    when 3 { @parts[0] }
    default { die "Too many commas in name <$str>" }
  }
}
