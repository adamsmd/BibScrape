unit module BibScrape::CommandLine;

class ParamInfo {
  has Bool:D $.named is required;
  has Str:D $.name is required;
  has Any:U $.type is required;
  has Any:_ $.default is required;
  has Pod::Block::Declarator:_ $.doc is required;
}

sub param-info(Parameter:D $param --> ParamInfo:D) {
  my Str:D $name = ($param.name ~~ /^ "{$param.sigil}{$param.twigil}" (.*) $/).[0].Str;
  my Any:_ $default = $param.default && ($param.default)();
  ParamInfo.new(
    named => $param.named, name => $name, type => $param.type,
    default => $default, doc => $param.WHY);
}

sub param-infos(Sub:D $main--> List:D) {
  my ParamInfo:D @param-info;
  my ParamInfo:D %param-info;
  # TODO: BEGIN
  for $main.signature.params -> Parameter:D $param {
    my ParamInfo:D $param-info = param-info($param);
    if $param.named {
      %param-info{$param-info.name} = $param-info;
    } else {
      push @param-info = $param-info;
    }
  }
  (@param-info, %param-info)
}

sub type-name(Any:U $type --> Str:D) {
  given $type {
    when Positional { type-name($type.of); }
    when IO::Path { 'File'; }
    default { $type.^name; }
  }
}

sub GENERATE-USAGE(Sub:D $main, |capture --> Str:D) is export {
  my List:D $infos = param-infos($main);
  my ParamInfo:D @param-info = $infos[0];
  my ParamInfo:D %param-info = $infos[1];
  my Int:D constant $end-col = 80;
  my $out = '';
  sub col(Int:D $col --> Any:U) {
    my Int:D $old-col = $out.split("\n")[*-1].chars;
    if $old-col > $col { $out ~= "\n"; $old-col = 0; }
    $out ~= ' ' x ($col - $old-col);
    return;
  }
  sub wrap(Int:D $start, Str:D $str is copy --> Any:U) {
    for $str.split( / ' ' * ';' ' '* / ) -> $paragraph is copy {
      $paragraph ~~ s:g/ ' '+ $//;
      if $paragraph eq '' {
        $out ~= "\n";
      } else {
        for $paragraph ~~ m:g/ (. ** {0..($end-col - $start)}) [ ' '+ | $ ] / -> $line {
          col($start);
          $out ~= $line;
        }
      }
    }
    return;
  }
  $out ~= "Usage:\n";
  $out ~= "  $*PROGRAM-NAME [options]";

  # TODO: %param-info
  for @param-info -> ParamInfo:D $param-info {
    $out ~= " <" ~ $param-info.name ~ ($param-info.type ~~ Positional ?? '> ...' !! '>');
  }

  wrap(0, $main.WHY.leading);

  for $main.signature.params -> Parameter:D $param {
    my $param-info = param-info($param);
    with $param-info.doc and $param-info.doc.leading {
      wrap(0, $_);
    }
    if $param-info.named {
      $out ~= " --{$param-info.name}";
      given $param-info.type {
        when Bool { }
        when Positional { $out ~= "=<{type-name($param-info.type)}> ..."; }
        default { $out ~= "=<{type-name($param-info.type)}>"; }
      }
    } else {
      given $param-info.type {
        when Positional {
          $out ~= " <{$param-info.name}> ...";
        }
        default {
          $out ~= " <{$param-info.name}>";
        }
      }
    }
    # TODO: comma in list keyword flags
    if $param-info.default.defined {
      wrap(28, "Default: {$param-info.default}");
    } else {
      $out ~= "\n";
    }
    $out ~= "\n";
    # if $param-info.type ~~ Enumeration {
    #   wrap(4, "<{type-name($param-info.type)}> = {$param-info.type.enums.keys.join(' | ')};");
    # }
    with $param-info.doc and $param-info.doc.trailing {
      wrap(4, $_);
    }
    $out ~= "\n";
  }
  wrap(0, $main.WHY.trailing);
  $out.chomp;
}

sub ARGS-TO-CAPTURE(Sub:D $main, @args is copy where { $_.all ~~ Str:D }--> Capture:D) is export {
  my List:D $infos = param-infos($main);
  my ParamInfo:D @param-info = $infos[0];
  my ParamInfo:D %param-info = $infos[1];
  my Bool:D $no-parse = False;
  my Int:D $positionals = 0;
  my Any:_ @param-value;
  my Any:_ %param-value = %param-info.map({ $_.key => $_.value.default });
  while @args {
    my Str:D $arg = shift @args;
    given $arg {
      # Positionals
      when $no-parse | !/^ '--' / {
        my $param = @param-info[$positionals];
        given $param.type {
          when Positional {
            @param-value[$positionals] = Array[$param.type.of].new()
              unless @param-value[$positionals];
            push @param-value[$positionals], ($param.type.of)($arg);
            # NOTE: no `$positionals++`
          }
          default {
            @param-value[$positionals] = ($param.type)($arg);
            $positionals++;
          }
        }
      }
      # --
      when /^ '--' $/ { $no-parse = True; }
      # Keyword
      when /^ '--help' | '-h' | '-?' $/ { %param-value<help> = True; }
      when /^ '--' ('/'?) (<-[=]>+) (['=' (.*)]?) $/ {
        my $polarity = ($0.chars == 0);
        say "==", $polarity;
        my $name = $1.Str;
        # TODO: when $name eq ''
        my $param = %param-info{$name}; # TODO: Missing param name
        my $info = %param-info{$name};
        given $info.type {
          when Positional {
            my Str:D $value-str = $2.[0].Str;
            if $value-str eq '' {
              if $polarity {
                %param-value{$info.name} = Array[$info.type.of].new();
              } else {
                %param-value{$info.name} = $info.default;
              }
            } else {
              # TODO: comma in field options
              my Any:D $value = ($info.type.of)($value-str);
              if $polarity {
                push %param-value{$info.name}, $value;
              } else {
                %param-value{$info.name} =
                  Array[$info.type.of](%param-value{$info.name}.grep({ not ($_ eqv $value) }));
              }
            }
          }
          default {
            my $value =
              $2.chars > 0 ?? $2.[0] !!
                $param.type ~~ Bool ?? $polarity.Str !! # TODO: yes, no
                @args.shift; # TODO: missing arg
            my $value2 = ($info.type)($value);
            %param-value{$info.name} = $value2;
          }
        }
      }
      default {
        die "impossible";
      }
    }
  }
  my $capture = Capture.new(list => @param-value, hash => %param-value);
  $capture;
}
