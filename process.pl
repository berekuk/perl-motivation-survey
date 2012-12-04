#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use IPC::System::Simple;
use autodie qw(:all);

use LWP::UserAgent;
use List::Util qw(sum);

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
    "Don't care",
    "Weakly motivating",
    "Motivating",
    "Strongly motivating",
    "It discourages me",
    "Doesn't apply",
    "N/A",
);

sub fetch_data {
    my $data_file = 'data';
    if ($ENV{REFETCH}) {
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
        "Last Page Accessed",
        "Created By",
        "Updated By",
        "IP Address",
        "Last Updated",
        "Completion Status",
        "Entry Id",
    ) {
        for my $entry (@$entries) {
            delete $entry->{$question} or die "Column '$question' not found";
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

    # current report doesn't contain any fields that need cleanup
    # but that can change in the future
    # cleanup_data($entries);

    return $entries;
}

sub print_reason_histogram {
    my ($entries, $reason) = @_;

    my %stat = map { $_ => 0 } @motivation_levels;
    $stat{ $_->{$reason} }++ for @$entries;

    $stat{"No answer"} = delete $stat{""} if $stat{""};

    say "$_\t$stat{$_}" for @motivation_levels;
}

sub slice {
    my ($entries, $question, $answers) = @_;

    my $slice = [];
    for my $entry (@$entries) {
        push @$slice, $entry if grep { $entry->{$question} eq $_ } @$answers;
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

    my $result = qx(Rscript -e '$command'); # FIXME - quote $command
    if ($?) {
        die "Rscript failed: $?";
    }
    return $result;
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

    for my $reason (@reasons) {

        my ($avg_first, $avg_second) = map {
            average_motiweight($_, $reason)
        } ($first, $second);

        my ($c_first, $c_second) = map {
            r_cstring(all_motiweights($_, $reason))
        } ($first, $second);

        # Welch's t test - check whether there's a significant difference between answers for two slices
        # see http://en.wikipedia.org/wiki/Welch%27s_t_test and http://stat.ethz.ch/R-manual/R-patched/library/stats/html/t.test.html for details
        my $pvalue = call_r("cat(t.test($c_first, $c_second)\$p.value)");

        if ($pvalue < $significant_level) {
            say "$reason ($avg_first vs $avg_second); p=$pvalue";
        }
    }
}

sub print_histograms {
    my ($entries) = @_;
    for my $reason (@reasons) {
        say "=== $reason ===";
        print_reason_histogram($entries, $reason);
        say '';
    }
}

sub print_slice_comparisons {
    my ($entries) = @_;

    my $newbies = slice(
        $entries,
        'How long have you been involved in the open source community?' => [
            'less than 1 year',
            '1-3 years',
        ]
    );
    my $experienced = slice(
        $entries,
        'How long have you been involved in the open source community?' => [
            #'4-6 years',
            #'7-10 years',
            'more than 10 years',
        ]
    );

    say "Newbies: ".scalar(@$newbies);
    say "Experienced: ".scalar(@$experienced);


    compare_slice_reasons($newbies, $experienced);
}

sub main {
    my $entries = load_data();

    print_histograms($entries);
    print_slice_comparisons($entries);
}

main unless caller;