#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use IPC::System::Simple;
use autodie qw(:all);

use LWP::UserAgent;
use List::Util qw(sum max);
use List::MoreUtils qw(uniq);
use Term::ANSIColor qw(:constants);
local $Term::ANSIColor::AUTORESET = 1;

use JSON;

my @reasons = (
    'Writing the code the way I want',
    'Making the world a better place',
    'Moral satisfaction',
    'Improving the software I use',
    'Learning',
    'Creativity',
    'Socializing',
    'Collaborating with other people',
    'Getting feedback',
    'Getting praise',
    'Building a career',
    'Making money',
    'Job requirement',
);

my @motivation_levels = (
    "Weakly motivating",
    "Motivating",
    "Strongly motivating",
    "It discourages me",
    "Don't care",
    "Doesn't apply",
    "N/A",
);

my $result = {
    motivation_levels => \@motivation_levels,
    reasons => \@reasons,
    q2a => {
        (map { $_ => \@motivation_levels } @reasons),
        'How often do you contribute to the open source, on average? (Coding, reporting bugs, writing blog posts all counts.)' => [
            'Almost daily',
            'Several times per week',
            'Several times per month',
            'Several times per year',
            'Even less often',
            'N/A',
        ],
        'Would you like to contribute more?' => [
            'Yes',
            'No',
            "I'd like to contribute less",
            'N/A',
        ],
        'Given the amount of free time you have now, would you contribute more if the environment was perfectly friendly, perfectly rewarding, and you knew that your actions make a great impact?' => [
            'No',
            'Probably',
            'Surely',
            'N/A',
        ],
        'How long have you been involved in the open source community?' => [
            "Don't remember / Don't want to answer",
            "less than 1 year",
            "1-3 years",
            "4-6 years",
            "7-10 years",
            "more than 10 years",
            'N/A',
        ],
    }
};

my $entries;
my @questions;

sub fetch_data {
    my $data_file = 'data';
    if ($ENV{REFETCH}) {
        # you may notice entry 56 is missing
        # that's ok, I manually removed it - it was double-posted
        my $response = LWP::UserAgent->new->get('http://berekuk.wufoo.eu/export/report/perl-motivation-raw-data.txt');
        die $response->status_line unless $response->is_success;
        open my $fh, '>', $data_file;
        print {$fh} $response->content;
        close $fh;
    }

    return qx(cat $data_file);
}

sub cleanup_data {
    my $entries = shift;

    for my $question (
        # these fields can't be quantified
        'List any other possible reasons for your participation:',
        "Anything else you'd like to share on the topic of this survey:",
        "CPAN ID, if you have one and you're ok with sharing it:",
        # technical fields from wufoo
        "Entry Id",
        "Date Created",
        "Last Page Accessed",
        "Completion Status",
    ) {
        for my $entry (@$entries) {
            delete $entry->{$question};
        }
    }
}

sub load_data {
    my $content = fetch_data();

    my @lines = split /\n/, $content;
    s/\r$// for @lines;

    my $columns_line = shift @lines;
    my @columns = split /\t/, $columns_line;

    my $entries = [];
    for my $line (@lines) {
        my @values = split /\t/, $line;

        my $entry = {};
        for my $cid (0 .. $#columns) {
            my $value = $values[$cid];
            $value = 'N/A' if $value eq '';

            $entry->{$columns[$cid]} = $value;
        }
        push @$entries, $entry;
    }

    cleanup_data($entries);
    @questions = grep { defined $entries->[0]{$_} } @columns;

    return $entries;
}

sub print_histogram {
    my ($entries, $question) = @_;

    my @options = @{ $result->{q2a}{$question} };

    my %stat = map { $_ => 0 } @options;
    for my $entry (@$entries) {
        my $answer = $entry->{$question};
        die "Unexpected answer '$answer'" unless defined $stat{$answer};
        $stat{$answer}++;
    }

    $stat{"No answer"} = delete $stat{""} if $stat{""};

    my $max_length = max(map { length } @options);
    my $max_ascii_width = 20;

    $result->{histogram}{$question} = \%stat;

    for (@options) {
        my $key = $_.(' ' x ($max_length - length($_)));
        my $value = $stat{$_}.(' ' x (3 - length($stat{$_})));
        my $ascii = '#' x int($max_ascii_width * $value / scalar @$entries);
        $ascii .= ' ' x ($max_ascii_width - length $ascii);
        $ascii = "|$ascii|";
        say "$key  $value  $ascii";
    }
}

sub slice {
    my ($entries, $question, $slice_answers) = @_;

    my %seen_answers;

    my $slice = [];
    for my $entry (@$entries) {
        my $answer = $entry->{$question};
        push @$slice, $entry if grep { $answer eq $_ } @$slice_answers;
        $seen_answers{$answer}++;
    }

    # sanity check - check that each slice_answer is seen at least once - that's true, afaik
    for my $slice_answer (@$slice_answers) {
        die "No answer '$slice_answer' is seen for the question '$question'" unless $seen_answers{$slice_answer};
    }

    return $slice;
}

sub motiweight {
    my ($level) = @_;
    if ($level eq 'Weakly motivating') {
        return 1;
    }
    if ($level eq "Motivating") {
        return 2;
    }
    if ($level eq "Strongly motivating") {
        return 3;
    }
    if ($level eq "It discourages me") {
        return -3;
    }

    # sanity check
    unless (grep { $level eq $_ } ("Don't care", "Doesn't apply", "N/A")) {
        die "Unexpected motivation level '$level'";
    }
    return 0;
}

sub all_motiweights {
    my ($entries, $reason) = @_;
    return map { motiweight($_->{$reason}) } @$entries;
}

sub average_motiweight {
    my ($entries, $reason) = @_;

    my @motiweights = all_motiweights($entries, $reason);
    return sum(@motiweights) / scalar(@motiweights);
}

# run Rscript and get its output
sub call_r {
    my ($command) = @_;

    my $output = qx(Rscript -e '$command'); # FIXME - quote $command
    if ($?) {
        die "Rscript failed: $?";
    }
    return $output;
}

# get c(...) code for Rscript
sub r_cstring {
    my @values = @_;
    return 'c('.join(',', @values).')';
}


sub compare_slice_reasons {
    my ($first, $second) = @_;

    my $significant_level = 0.1;
    say "Statistically significant differences (p < $significant_level):";

    my $total = 0;
    my @result;
    for my $reason (@reasons) {

        my ($avg_first, $avg_second) = map {
            sprintf("%.4f", average_motiweight($_, $reason))
        } ($first, $second);

        my ($c_first, $c_second) = map {
            r_cstring(all_motiweights($_, $reason))
        } ($first, $second);

        # Welch's t test - check whether there's a significant difference between answers for two slices
        # see http://en.wikipedia.org/wiki/Welch%27s_t_test and http://stat.ethz.ch/R-manual/R-patched/library/stats/html/t.test.html for details
        my $pvalue = call_r("cat(t.test($c_first, $c_second)\$p.value)");
        my $confidence = sprintf "%.4f", 1 - $pvalue;

        if ($pvalue < $significant_level) {
            say "* $reason ($avg_first vs $avg_second); confidence=$confidence";
            push @result, {
                reason => $reason,
                averages => [$avg_first, $avg_second],
                confidence => $confidence,
            };
        }
    }
    unless (@result) {
        say "* none";
    }
    return @result;
}

sub print_all_histograms {
    my ($entries) = @_;
    for my $question (@questions) {
        say GREEN "=== $question ===";
        print_histogram($entries, $question);
        say '';
    }
}

sub compare_by_question {
    my ($entries, $question, $first_set, $second_set) = @_;

    my ($first_slice, $second_slice) = map {
        slice(
            $entries,
            $question => $_
        );
    } ($first_set, $second_set);

    say GREEN "Comparing the reasons by how people answer the '$question' question";
    say "First group: [", join('; ', @$first_set), "], total: ", scalar(@$first_slice);
    say "Second group: [", join('; ', @$second_set), "], total: ", scalar(@$second_slice);

    my @compare_result = compare_slice_reasons($first_slice, $second_slice);
    push @{ $result->{compares} }, {
        question => $question,
        sets => [$first_set, $second_set],
        group_sizes => [ map { scalar @$_ } ($first_slice, $second_slice) ],
        result => \@compare_result,
    };
    say '';
}

sub print_slice_comparisons {
    my ($entries) = @_;

    compare_by_question(
        $entries,
        'How long have you been involved in the open source community?',
        [
            'less than 1 year',
            '1-3 years',
            '4-6 years',
        ],
        [
# ignoring people in the middle to increase the gap and get more statistically significant results
#            '7-10 years',
            'more than 10 years',
        ]
    );

    compare_by_question(
        $entries,
        'How often do you contribute to the open source, on average? (Coding, reporting bugs, writing blog posts all counts.)',
        [
            'Almost daily',
            'Several times per week',
        ],
        [
#            'Several times per month',
            'Several times per year',
            'Even less often',
        ]
    );

    compare_by_question(
        $entries,
        'Would you like to contribute more?',
        [
            'Yes',
        ],
        [
            'No',
            "I'd like to contribute less",
        ]
    );
}

sub print_correlations {
    my ($entries) = @_;

    my $significant_level = 0.3;
    say GREEN "==== Correlations ====";
    for my $i (0 .. $#reasons) {
        for my $j ($i + 1 .. $#reasons) {
            my ($reason1, $reason2) = ($reasons[$i], $reasons[$j]);
            my ($c1, $c2) = map {
                r_cstring(all_motiweights($entries, $_))
            } ($reason1, $reason2);

            my $cor = call_r("cat(cor($c1, $c2))");
            next unless $cor > $significant_level;
            say "Correlation($reason1, $reason2): $cor";
        }
    }
    say '';
}

sub print_dominations {
    my ($entries) = @_;

    my $significant_level = 5;
    say GREEN "==== Dominations ====";
    say "Displaying the reason pairs where the number of responders for which the first reason is more important than the second";
    say "is at least $significant_level times more than the number of responders for which the second reason is more important";
    say "Legend: [number of resonders with a>b, with a=b, with a<b]";
    say '';
    for my $i (0 .. $#reasons) {
        for my $j ($i + 1 .. $#reasons) {
            my ($reason1, $reason2) = ($reasons[$i], $reasons[$j]);

            my ($gt, $lt, $eq) = (0, 0, 0);
            for my $entry (@$entries) {
                my ($m1, $m2) = map { motiweight($entry->{$_}) } ($reason1, $reason2);
                my $cmp = $m1 <=> $m2;
                $gt++ if $m1 > $m2;
                $lt++ if $m1 < $m2;
                $eq++ if $m1 == $m2;
            }

            if ($gt < $lt) {
                ($gt, $lt) = ($lt, $gt);
                ($reason1, $reason2) = ($reason2, $reason1);
            }

            if (
                ($gt / $lt) > $significant_level
            ) {
                say "[$gt, $eq, $lt] $reason1 > $reason2";
                push @{$result->{dominations}}, {
                    gt => $gt,
                    eq => $eq,
                    lt => $lt,
                    left => $reason1,
                    right => $reason2,
                };
            }
        }
    }
}

sub print_txt {
    my ($type) = @_;
    open my $fh, '<', $type;
    while (my $reason = <$fh>) {
        chomp $reason;
        $reason =~ s/\\n/\n/g;
        say $reason;
        say "---";

        # so far all links in comments (all 2 of them) have been at the end of line, so we can be greedy
        $reason =~ s{(http://.*)}{<a href="$1">$1</a>}g;

        # we wrap reasons in <pre>, so this is not necessary
        $reason =~ s/\n/<br>/g;

        push @{ $result->{$type} }, $reason;
    }
    close $fh;
}

sub print_other_reasons {
    say GREEN "==== Other reasons for participation ====";
    print_txt('other-reasons');
}

sub print_comments {
    say GREEN "==== Comments ====";
    print_txt('comments');
}

sub generate_json {
    my $json = JSON->new->utf8->pretty->encode($result);
    open my $fh, '>', 'results.json';
    print {$fh} "var r = $json;";
    close $fh;
}

sub main {
    my $entries = load_data();
    $result->{entries} = $entries;

    print_all_histograms($entries);
    print_slice_comparisons($entries);
    print_correlations($entries);
    print_dominations($entries);

    print_other_reasons();
    print_comments();

    generate_json();
}

main unless caller;
