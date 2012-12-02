#!/usr/bin/env perl

use strict;
use warnings;

use 5.010;

use LWP::UserAgent;

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
    my $response = LWP::UserAgent->new->get('http://berekuk.wufoo.eu/export/report/perl-motivation-raw-data.txt');
    die $response->status_line unless $response->is_success;
    return $response->content;
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
    my ($entries, $question, $answer) = @_;

    return [
        grep { $_->{$question} eq $answer } @$entries
    ];
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
        return -1;
    }

    # sanity check
    unless (grep { $level eq $_ } ("Don't care", "Doesn't apply", "N/A")) {
        die "Unexpected motivation level '$level'";
    }
    return 0;
}

sub average_motiweight {
    my ($entries, $reason) = @_;

    my $total = 0;
    for my $entry (@$entries) {
        $total += motiweight($entry->{$reason});
    }
    return $total / scalar @$entries;
}

sub compare_slice_reasons {
    my ($first, $second) = @_;

    for my $reason (@reasons) {
        my ($x, $y) = map { average_motiweight($_, $reason) } ($first, $second);
        warn "$reason ($x, $y)";
        # TODO - use Welch's t test to check whether there's a significant correlation
        # http://en.wikipedia.org/wiki/Welch%27s_t_test
        #
        # Alternatively, we can avoid creating two different slices,
        # and just check for the correlation between the slice criteria and the motiweigt,
        # if the slice criteria is somewhat quantifiable and not just boolean.
    }
}

sub main {
    my $entries = load_data();

    for my $reason (@reasons) {
        say "=== $reason ===";
        print_reason_histogram($entries, $reason);
        say '';
    }

    my ($newbies, $e13, $e46, $e710, $experienced) = map {
        slice($entries, 'How long have you been involved in the open source community?' => $_),
    } (
        'less than 1 year',
        '1-3 years',
        '4-6 years',
        '7-10 years',
        'more than 10 years',
    );
    push @$newbies, @$e13;
    push @$newbies, @$e46;
    push @$experienced, @$e710;

    say "Newbies: ".scalar(@$newbies);
    say "Experienced: ".scalar(@$experienced);

    compare_slice_reasons($newbies, $experienced);
}

main unless caller;
