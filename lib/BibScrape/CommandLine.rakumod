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
  my Str:D $out = '';
  sub col(Int:D $col --> Any:U) {
    my Int:D $old-col = $out.split("\n")[*-1].chars;
    if $old-col > $col { $out ~= "\n"; $old-col = 0; }
    $out ~= ' ' x ($col - $old-col);
    return;
  }
  sub wrap(Int:D $start, Str:D $str is copy --> Any:U) {
    for $str.split( / ' ' * ';' ' '* / ) -> Str:D $paragraph is copy {
      $paragraph ~~ s:g/ ' '+ $//;
      if $paragraph eq '' {
        $out ~= "\n";
      } else {
        for $paragraph ~~ m:g/ (. ** {0..($end-col - $start)}) [ ' '+ | $ ] / -> Str:D(Match:D) $line {
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
    my ParamInfo:D $param-info = param-info($param);
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
        when Positional { $out ~= " <{$param-info.name}> ..."; }
        default { $out ~= " <{$param-info.name}>"; }
      }
    }
    # TODO: comma in list keyword flags
    if $param-info.default.defined {
      if $param-info.type ~~ Positional {
        wrap(28, "Default: {$param-info.default.map({ "'$_'" })}");
      } else {
        wrap(28, "Default: {$param-info.default}");
      }
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
  sub def(ParamInfo:D $param-info) {
    $param-info.default
      // ($param-info.type ~~ Positional
        ?? Array[$param-info.type.of].new()
        !! $param-info.type);
  }
  my Any:_ @param-value = @param-info.map(&def);
  my Any:_ %param-value = %param-info.map({ $_.key => def($_.value) });
  while @args {
    my Str:D $arg = shift @args;
    given $arg {
      # Positionals
      when $no-parse | !/^ '--' / {
        my ParamInfo:D $param-info = @param-info[$positionals];
        given $param-info.type {
          when Positional {
            push @param-value[$positionals], ($param-info.type.of)($arg);
            # NOTE: no `$positionals++`
          }
          default {
            @param-value[$positionals] = ($param-info.type)($arg);
            $positionals++;
          }
        }
      }
      # Bare '--'
      when /^ '--' $/ { $no-parse = True; }
      # Help
      when /^ '--help' | '-h' | '-?' $/ { %param-value<help> = True; }
      # Keyword
      when /^ '--' ('/'?) (<-[=]>+) (['=' (.*)]?) $/ {
        my Bool:D $polarity = ($0.chars == 0);
        my Str:D $name = $1.Str;
        # TODO: when $name eq ''
        my ParamInfo:D $param-info = %param-info{$name}; # TODO: Missing param name
        given $param-info.type {
          when Positional {
            my Str:D $value-str = $2.[0].Str;
            if $value-str eq '' {
              if $polarity {
                %param-value{$param-info.name} = Array[$param-info.type.of].new();
              } else {
                %param-value{$param-info.name} = def($param-info);
              }
            } else {
              # TODO: comma in field options
              my Any:D $value = ($param-info.type.of)($value-str);
              if $polarity {
                push %param-value{$param-info.name}, $value;
              } else {
                %param-value{$param-info.name} =
                  Array[$param-info.type.of](
                    %param-value{$param-info.name}.grep({ not ($_ eqv $value) }));
              }
            }
          }
          default {
            my Str:D $value =
              $2.chars > 0 ?? $2.[0].Str !!
                $param-info.type ~~ Bool ?? $polarity.Str !! # TODO: yes, no
                @args.shift; # TODO: missing arg
            my Any:D $value2 = ($param-info.type)($value);
            %param-value{$param-info.name} = $value2;
          }
        }
      }
      default {
        die "impossible";
      }
    }
  }
  my Capture:D $capture = Capture.new(list => @param-value, hash => %param-value);
  $capture;
}
