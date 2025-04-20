#!/usr/bin/perl

# tty PONG by Benjamin Newman, September 2003, revised April 2004
#
#        usage: pong [-qt] <opponent>
#        -t: test mode (play against same user)
#        -q: quiet mode (don't send bells)
#
# This program implements the classic game PONG so that it can be played on a
# tty between two players logged in to the same UNIX system.
#
# For single-user debugging, use: "pong -t <session>" in one terminal, and
# "pong <session>" (without the "-t") from another terminal of the same user.
# <session> can be any string without spaces other than your own username.
#
# This program requires the unix commands "write", "mkfifo", and "stty".
#
# COPYING: You are free to copy this file and distribute it without
# modification.  You may also modify it for your own use without restriction.
# If you distribute a modified version of this file, you must add a comment
# below this section documenting your changes.  You may not modify this
# license paragraph.
#
# -- Benjamin Newman ( bnewman AT sccs DOT swarthmore DOT edu 

$this_game = "pong";

sub setup {
    %cswitch = ();
    if ($ARGV[0] =~ /^-/) {
        $cswitch{$_} = 1 foreach (split //, shift @ARGV);
    }
    $beep = ($cswitch{"q"}) ? "" : chr 7;
    $myself = getpwuid $<;
    $my_foe = $ARGV[0];
    die "Usage: \$this_game [options] <opponent>\n" unless ($my_foe);
    ($myself, $my_foe) = ($my_foe, $myself) if ($cswitch{"t"});
    $esc = chr 27;
    $deg = "$esc(0f$esc(B";
    $delay = 0.045;
}

sub cook_io {
    if (shift) {
        $| = 1;
        system "stty", "icanon";
        system "stty", "echo";
    }
    else {
        $| = 1;
        system "stty", "-icanon";
        system "stty", "-echo";
    }
}

sub read_char {
    my $fh = shift;
    my $mask = my $k = "";
    vec($mask, fileno($fh), 1) = 1;
    $k = getc($fh) if (vec ((select $mask,undef,undef,0.01), fileno($fh), 1));
    return $k;
}

sub handshake {
    my $player = 0;
    my $tmp_dir = "/tmp/" . (join "-v-", (sort $myself, $my_foe)) . ".$this_game";
    my $umask = umask 0;
    if (-d $tmp_dir) {
        system "mkfifo", "$tmp_dir/$myself-to-$my_foe";
        system "mkfifo", "$tmp_dir/$my_foe-to-$myself";

        open IPC_OUT, "> $tmp_dir/$myself-to-$my_foe";
        open IPC_IN, "< $tmp_dir/$my_foe-to-$myself";

        unlink "$tmp_dir/$myself-to-$my_foe";
        unlink "$tmp_dir/$my_foe-to-$myself";

        $player = 1;
    }
    else {
        open WRITE_FH, "| write $my_foe";
        my $oldfh = select WRITE_FH;
        print "I, $myself, challenge you, $my_foe, to a game of $this_game!\n";
        print "To accept the challenge, type: $this_game $myself\n";
        select $oldfh;
        close WRITE_FH;

        mkdir $tmp_dir;

        print "Waiting for $my_foe to answer your $this_game challenge... (Hit 'q' to abort)\n";
        cook_io(0);
        until (-e "$tmp_dir/$myself-to-$my_foe") {
            if (read_char("STDIN") eq "q") {
                rmdir $tmp_dir;
                print "You aborted the game of $this_game before $my_foe answered your challenge.\n";
                exit 0;
            }
        }
        cook_io(1);

        open IPC_IN, "< $tmp_dir/$my_foe-to-$myself";
        open IPC_OUT, "> $tmp_dir/$myself-to-$my_foe";

        while (-e "$tmp_dir/$myself-to-$my_foe") {
        }
        rmdir $tmp_dir;
    }
    umask $umask;

    my $oldfh = select IPC_OUT;
    $| = 1;
    select $oldfh;
    return $player;
}

sub setup_game {

    # Print instructions:

    print 
        "$esc\[H$esc\[0J       PONG Instructions:\n\n",
        "This game is designed to use a tty\n",
        "at least 24 rows by 36 columns, so\n",
        "set your window size accordingly.\n\n",
        "'.' (period) = right   'r' = redraw\n",
        "                       'p' = pause\n",
        "',' (comma)  = left    'q' = quit\n\n",
        "Hit the ball with your paddle, the\n",
        "one at the bottom of the screen.\n",
        "To make the ball go left or right,\n",
        "hit it with that end of the paddle.\n\n",
        "When you miss, your opponent will\n",
        "score, the ball will bounce off the\n",
        "wall behind you, and the game will\n",
        "continue without interruption - so\n",
        "don't blink!  Game is to 10 points.\n\n",
        "$esc\[7mPress any key when ready to begin.$esc\[0m\n";

    # Wait for each player to press a key:

    cook_io(0);

    $x = $y = "";
    print IPC_OUT "$x\n";
    until ((($_ = <IPC_IN>) ne "\n") && ($x ne "")) {
        $y = read_char("STDIN");
        $y =~ tr/\n/\ /;
        if ($x eq "" and $y ne "") {
            $x = $y;
            print "Waiting for opponent to be ready.";
        }
        print IPC_OUT "$x\n";
    }

    # initialize game state

    $timer = 0;

    %score = ($myself => 0, $my_foe => 0);
    %padpos = ($myself => 0, $my_foe => 0);
    @padstr = ('=====', '&*$!%');
    %missed = ($myself => 0, $my_foe => 0);

    @x_vel = ([0,0,0,0,0,0],
              [0,0,1,0,0,1],
              [0,1,0,1,0,1],
              [0,1,1,0,1,1],
              [1,1,1,1,1,1],
              [1,1,1,1,1,1],
              [1,1,1,1,1,1],
              [1,1,1,1,1,1]);
    
    @y_vel = ([1,1,1,1,1,1],
              [1,1,1,1,1,1],
              [1,1,1,1,1,1],
              [1,1,1,1,1,1],
              [1,1,1,1,1,1],
              [0,1,1,0,1,1],
              [0,1,0,1,0,1],
              [0,0,1,0,0,1]);
    
    @bounce = ([-7,-7,-6,-6,-5,-5,-4,-4,-3,-2,-1,0,1,2,3],
               [-6,-5,-4,-4,-3,-3,-3,-2,-2,-1,0,1,2,3,4],
               [-5,-4,-3,-2,-2,-1,-1,0,1,1,2,2,3,4,5],
               [-4,-3,-2,-1,0,1,2,2,3,3,3,4,4,5,6],
               [-3,-2,-1,0,1,2,3,4,4,5,5,6,6,7,7]);

    # Choose initial ball state:

    if ($player == 0) {
        $dy = (int rand 2);
        $ball_y = $dy + 20;
        $dy = $dy * 2 - 1;

        $dx = (int rand 15) - 7;

        print IPC_OUT "$dy:$dx:$ball_y\n";
    }
    else {
        chomp ($get_start = <IPC_IN>);
        ($dy, $dx, $ball_y) = split ":", $get_start;
        $ball_y = 41 - $ball_y;
        $dy = 0 - $dy;
    }

    $old_x = $ball_x;
    $old_y = $ball_y;

    $nbeeps = 0;

    display_state(1);

    # Countdown to game start:

    for ($i = 3; $i > 0; $i--) {
    
        print $esc, "[13;18H$i", $esc, "[24;35H|$beep";
        select undef, undef, undef, 1.0;
        print IPC_OUT "$i\n";
        scalar <IPC_IN>;
    }
    print "$esc\[13;18H$beep$beep$beep";

    display_state(0);
}

sub display_state {
    $display = "";
    if (shift) {
        # redraw whole screen

        $display .= "$esc\[H$esc\[0J$esc\[7m$myself: $score{$myself}";
        $display .= " " x (12 - length($myself));
        $display .= "PONG!";
        $display .= " " x (12 - length($my_foe));
        $display .= "$my_foe: $score{$my_foe}$esc\[0m";
        for ($i = 2; $i <= 24; $i++) {
            $display .= "$esc\[$i;0H|$esc\[$i;35H|";
        }
    }
    # draw just the moving bits
    $display .= "$esc\[1;" . (length($myself) + 3) . "H$esc\[7m" . $score{$myself};
    $display .= "$esc\[1;35H" . $score{$my_foe} . "$esc\[0m";

    $display .= "$esc\[" . (int ($old_y/2) + 3) . ";" . ($old_x + 18) . "H ";
    $display .= "$esc\[" . (int ($ball_y/2) + 3) . ";" . ($ball_x + 18) . "H";
    $display .= ($move{$my_foe} eq "p") ? "P" : (($ball_y % 2) ? '.' : $deg);

    $display .= ($esc . "[2;1H|" . (" " x (14 + $padpos{$my_foe})) .
                 $padstr[$missed{$my_foe} cmp 0] .
                 (" " x (14 - $padpos{$my_foe})) . "|");
    $display .= ($esc . "[24;1H|" . (" " x (14 + $padpos{$myself})) .
                 $padstr[$missed{$myself} cmp 0] .
                 (" " x (14 - $padpos{$myself})) . "|");


    $display .= "$esc\[24;35H|" . ($beep x $nbeeps);
    print $display;
}

sub hash_state {
    my $hash = "";
    if (shift) {
        # create hash of game state according to opponent

        $hash = (join ":", $ball_x, (41 - $ball_y), $dx, (0 - $dy),
                 $padpos{$myself}, $padpos{$my_foe},
                 $score{$myself}, $score{$my_foe}, $timer);
    }
    else {
        # create hash of game state according to myself

        $hash = (join ":", $ball_x, $ball_y, $dx, $dy,
                 $padpos{$my_foe}, $padpos{$myself},
                 $score{$my_foe}, $score{$myself}, $timer);
    }
    return $hash . "\n";
}

sub update_state {

    $nbeeps = 0;

    foreach (keys %padpos) {
        $padpos{$_}-- if (($move{$_} eq ",") and ($padpos{$_} > -14));
        $padpos{$_}++ if (($move{$_} eq ".") and ($padpos{$_} < 14));
        $missed{$_} -= $missed{$_} <=> 0;
    }

    # Ball movement;

    $old_x = $ball_x;
    $old_y = $ball_y;

    $ball_x += ($x_vel[abs($dx)][($timer % 6)] * ($dx <=> 0));
    $ball_y += ($y_vel[abs($dx)][($timer % 6)] * $dy);

    # Hit detection;

    if (abs($ball_x) > 16) {
        $nbeeps = 1;
        $ball_x -= ($ball_x <=> 0);
        $dx = 0 - $dx;
    }
    if ($ball_y < 0) {
        $nbeeps = 1;
        $ball_y = 0;
        $dy = 0 - $dy;
        $dist = $ball_x - $padpos{$my_foe};
        if (abs($dist) > 2) {
            $missed{$my_foe} = 10;
            $score{$myself}++;
            $nbeeps = 3;
        }
        else { $dx = $bounce[$dist+2][$dx+7]; }
    }
    if ($ball_y > 41) {
        $nbeeps = 1;
        $ball_y = 41;
        $dy = 0 - $dy;
        $dist = $ball_x - $padpos{$myself};
        if (abs($dist) > 2) {
            $missed{$myself} = 10;
            $score{$my_foe}++;
            $nbeeps = 3;
        }
        else { $dx = $bounce[$dist+2][$dx+7]; }
    }

    $timer++;
}

sub get_move {
    my $k = read_char("STDIN");
    return (($k cmp chr 32) * ($k cmp chr 127) == -1) ? $k : "";
}

sub check_endcond {
    # check if a game end condition obtains, and if so return it
    return "You aborted the game." if ($move{$myself} eq "q");
    return "Your opponent aborted the game." if ($move{$my_foe} eq "q");
    foreach (keys %score) {
        return "$_ is the winner!" if ($score{$_} == 10);
    }
    return "";
}

sub play_game {
    setup_game();
    for (;;) {
        select undef, undef, undef, $delay if $delay;
        $move{$myself} = get_move();
        print IPC_OUT $move{$myself}, "\n";
        chomp ($move{$my_foe} = <IPC_IN>);
        print IPC_OUT hash_state(0);
        return "ERR: game state mismatch" if (<IPC_IN> ne hash_state(1));

        update_state();

        if ($move{$myself} eq "p") {
            print $esc, "[13;2HPaused, press [space] to resume.";
            $x = "";
            $x = read_char("STDIN") while ($x ne " ");
            $move{$myself} = "r";
        }

        display_state($move{$myself} eq "r");

        return $outcome if ($outcome = check_endcond());
    }
}

sub game_end {
    # exit depending on game end condition reported
    $outcome = shift;
    print "$esc\[13;2H$outcome\n";
    print "$esc\[14;4HPress [space] to exit.";
    $x = "";
    $x = read_char("STDIN") while ($x ne " ");
    print "$esc\[24;36H\n";
}

setup();
$player = handshake();
game_end(play_game());

cook_io(1);
