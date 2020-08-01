unit module BibScrape::Names;

# See:
# - https://github.com/aclements/biblib/blob/master/biblib/algo.py
# - https://maverick.inria.fr/~Xavier.Decoret/resources/xdkbibtex/bibtex_summary.html
# - https://www.ctan.org/tex-archive/info/bibtex/tamethebeast/

sub depths(Str:D $str --> Array:D[Int:D]) {
  my Int:D @depths;
  my Int:D $depth = 0;
  for $str.split('', :skip-empty) -> Str:D $char {
    push @depths, $depth;
    given $char {
      when '{' { $depth++; pop @depths; push @depths, $depth }
      when '}' { $depth-- }
    }
  }
  @depths;
}

sub depth-split(Str:D $str, Regex:D $regex --> Array:D[Str:D]) {
  my Int:D @depths = depths($str);
  my Int:D @positions =
    (0,
      ($str ~~ m:g/ $regex /)
        .grep({ !@depths[$_.from] })
        .map({ (.from - 1, .to) }).flat,
      $str.chars).flat;
  my Str:D @parts = @positions.map(
    sub (Int:D $from, Int:D $to --> Str:D) { $str.substr($from..$to) });
  @parts;
}

sub split-name(Str:D $str --> Array:D[Str:D]) is export {
  depth-split($str, rx/ \s* ',' \s* /);
}

sub split-names(Str:D $str --> Array:D[Str:D]) is export {
  depth-split($str, rx/ \s+ 'and' \s+ /);
}

# TODO: note that these are not exactly how BibTeX parses names, but they are good enough for us (because we avoid capitalization distinctions)
# TODO: factor out common code
sub flatten-name(Str:D $str --> Str:D) is export {
  my Str:D @parts = split-name($str.trim);
  do given @parts.elems {
    when 1 { "@parts[0]" }
    when 2 { "@parts[1] @parts[0]" }
    when 3 { "@parts[2] @parts[0] @parts[1]" }
    default { die "Too many commas in name <$str>" }
  }
}

# TODO: note that this may not include the 'von' (but only when in no-comma form)
sub order-name(Str:D $str --> Str:D) is export {
  my Str:D @parts = split-name($str.trim);
  do given @parts.elems {
    when 1 {
      my Str:D @words = depth-split(@parts[0], rx/ \s+ /);
      @words[*-1] ~ ', ' ~ @words[0..^*-1].join( ' ' )
    }
    when 2 { "@parts[0], @parts[1]" }
    when 3 { "@parts[0], @parts[1], @parts[2]" }
    default { die "Too many commas in name <$str>" }
  }
}

# TODO: note that this may include the 'von' (but not when in no-comma form)
sub last-name(Str:D $str --> Str:D) is export {
  my Str:D @parts = split-name($str.trim);
  do given @parts.elems {
    when 1 {
      my Str:D @words = depth-split(@parts[0], rx/ \s+ /);
      @words[*-1]
    }
    when 2 { @parts[0] }
    when 3 { @parts[0] }
    default { die "Too many commas in name <$str>" }
  }
}
