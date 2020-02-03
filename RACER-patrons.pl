#!/usr/bin/perl -w
#
# RACER-patrons.pl
#
# Purpose: To retrieve a patron data report from Alma Analytics, which is then transformed and delivered to the RACER ILL format.
# Method:  A daily report is run via Alma Analytics which generates a tab-delimited file and puts it on the SFTP server.
#          This script logs into the SFTP server, retrieves the file, and confirms the correct ID format and creates a unioversal expiry date for all users without expiry dates.
#          The updated list is written to a file on the SFTP server.
#          A log file is generated.
#          The file is trasferred via FTP to the Scholars Portal server.

use strict;                     # Good practice
use warnings;                   # Good practice
use lib qw(PATH_TO_CUSTOM_MODULES);        # CUSTOMIZE: Create path to custom modules if needed
use Net::SFTP::Foreign;         # From CPAN
use Time::HiRes;                # Perl core module
use Net::FTP;                   # Perl core module

# Download the daily file each time, even though it will only be updated once per day.
my $sftp = Net::SFTP::Foreign->new('FTP_ADDRESS', user => 'FTP_USER', key_path => 'PATH_TO_PRIVATE_KEY_FILE');  # CUSTOMIZE: need credentials and access to private key file (.ppk) 
$sftp->get('PATH_TO_REMOTE_ANALYTICS_REPORT', 'PATH_TO_LOCAL_ANALYTICS_REPORT');  # CUSTOMIZE: need localtion of Analytics file and where you're going to store it locally

my $verbose = 0;
my $start = Time::HiRes::gettimeofday();
my $now_string = localtime;  # e.g., "Mon Sep 23 18:47:34 2017"
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$year += 1900;
$mon = sprintf("%02d", ($mon+1));
$mday = sprintf("%02d", $mday);
my @months = qw ( JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC );

# flush output
$| = 1;

open (LOG, '>>PATH_TO_LOG_FILE' ) or die "Can't open RACER patron logfile: $!"; # CUSTOMIZE
open (RACERANALYTICS, '<:encoding(UTF-16)', 'PATH_TO_LOCAL_ANALYTICS_REPORT' ) or die "Can't open the RACER patrons file from Analytics: $!"; # CUSTOMIZE
open (RACERLEGACY, '>PATH_TO_LOCAL_FILE_FOR_RACER' ) or die "Can't write to RACER patron legacy file: $!"; # CUSTOMIZE
print LOG "Beginning to build RACER patron legacy file: $now_string\n";

my @field;
my ($lineCtr, $user_index, $expiry_index, $status_index, $i, $legacy_expiry);

while (<RACERANALYTICS>) {
	my $curLine = $_;
	$lineCtr++;
	$curLine =~ s/\s+$//;
	@field = split(/\t/,$curLine);
	if ($lineCtr == 1) {
		# Determine which columns contain the 'Primary Identifier', 'Status' and 'Expiry Date'
		for ($i=0;$i<(scalar(@field)-1);$i++) {
			$user_index = $i if ($field[$i] eq 'Primary Identifier');
			$expiry_index = $i if ($field[$i] eq 'Expiry Date');
			$status_index = $i if ($field[$i] eq 'Status');
		}
		# No column headers are added to the legacy file.
	} else {
		# Output the user account in the legacy format:
		# PRIMARY_ID|EXPIRY_DATE [DD-mmm-YYYY]
		if ($field[$user_index] =~ /^0[0-9]{6}$/) {
			if ($field[$expiry_index]) {
				$legacy_expiry = legacy_date_transform($field[$expiry_index]);
			} else {
				$legacy_expiry = legacy_date_transform('DEFAULT');			
			}
			print RACERLEGACY $field[$user_index] . '|' . $legacy_expiry . "\n";
		} else {
			print LOG "Rejecting user with non-Colleague pattern in Alma Primary ID field: $field[$user_index]\n";
		}
	}
}

close RACERANALYTICS;
close RACERLEGACY;

$sftp->put('PATH_TO_LOCAL_FILE_FOR_RACER', 'PATH_TO_REMOTE_FILE_FOR_RACER');
my $ftp = Net::FTP->new("ftp.scholarsportal.info", Debug => 0, Port => 21 ) or ftp_fail("Cannot connect to ftp.scholarsportal.info: $@");
$ftp->login('SP_USER','SP_PASSWORD') or ftp_fail("Cannot login ", $ftp->message);  # CUSTOMIZE
$ftp->binary() or ftp_fail("Cannot change to binary mode ", $ftp->message);
$ftp->passive() or ftp_fail("Cannot change to passive mode ", $ftp->message);
$ftp->put('PATH_TO_LOCAL_FILE_FOR_RACER') or ftp_fail("get failed ", $ftp->message); # CUSTOMIZE [assumes file is going into the root of the SP user directory]
$ftp->quit;

my $interval = Time::HiRes::gettimeofday();
print LOG "Processed $lineCtr records. Time elapsed: " . sprintf("%.2f", $interval - $start) . "\n\n";
close LOG;
exit(0);

sub legacy_date_transform {
	my $date = shift;
	my ($expiry_day,$expiry_month,$expiry_year);
	if ($date eq 'DEFAULT') {
	# Set to October 31 of following calendar year
		$expiry_day = '31';
		$expiry_month = 'OCT';
		$expiry_year = $year+1;
	} else {
	# Use expiry date from Alma. Sent as YYYY-MM-DD
		$expiry_day = substr($date,8,2);
		$expiry_month = $months[substr($date,5,2)-1];
		$expiry_year = substr($date,0,4);		
	}
	return "$expiry_day-$expiry_month-$expiry_year";
}
		
sub ftp_fail {
		my $message = shift;
		print LOG "$message\n";
		exit(0)
}
	