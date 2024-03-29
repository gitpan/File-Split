package File::Split;

use Data::Dumper;
use File::Basename;
use Array::Dissect qw( :all );
use POSIX qw(ceil floor);

use strict;
use warnings;

our $VERSION = '0.30';

sub new {
    my $class   = shift;
    my %args = ref($_[0])?%{$_[0]}:@_;
    my $self = \%args;


    bless $self, $class;
    return $self;
};


# Splits a file based on innumerable parameters.
# Check the perldocs for use information.
sub split_file
{
    my $self = shift;
    my $args = shift;          # how many parts to split
    
    my @out_files;          # Array of filenames that were generated.
    
    
    my $in_file = shift; 

    return unless $in_file; # No file to split


    if (($args->{'parts'})||($args->{'lines'}))
    {
        
        open my $in_fh, $in_file or return(undef);
        my @out_data = <$in_fh>;   
        close $in_fh;

        my $parts;
        my $size;

        # Given either 'parts' or 'lines' calculate the other.
        if ($args->{'parts'})
        {
            $parts = $args->{'parts'};
            $size = int(@out_data / $parts)+1;
        } elsif ($args->{'lines'})
        {
            $size = $args->{'lines'};
            $parts = int( @out_data/$size ) + 1;
        }
        
        my @slices;

        # Array::Dissect can't be used on an empty array.
        @slices = reform( $size, @out_data) if (@out_data);

        
        # If the array slicing under-generates arrays for the required number of parts, add on some empty ones.
        # Only really used for generating files from an empty (or near empty) file.
        while (@slices < $parts)
        {
            $slices[@slices] = [];
        }
        
        for (my $x=1;$x<=@slices;$x++)
        {
            my $out_data_str = join('',@{$slices[$x-1]});   # Convert data to string
            my $out_file = "$in_file.".$x;
            open my $fh, "> $out_file" or warn "Cannot write to $out_file: $!";
            print $fh $out_data_str;
            $out_files[@out_files] = $out_file;    ### Track generated files.
            
        }
        
        

        unlink($in_file) unless ($self->{'keepSource'});

    } elsif($args->{'grep'}||$args->{'substr'}) 
    {
        my $file_data;  # The lines will go in here.

        #Ensure creation of each requested sunbstring file.
        # Bad code taste
        if ($args->{'substr'})
        {
            my $vals = ref($args->{'substr'}->{'val'})?$args->{'substr'}->{'val'}:[$args->{'substr'}->{'val'}];
            foreach my $val (@{$vals})
            {
                $file_data->{$val} = '';
            }
        }

        open my $in_fh, $in_file or return(undef);
        while (my $line = <$in_fh>)
        {
            print $line;
            if (ref($args->{'grep'}) eq 'HASH')
            {
                # User passed in a hash of regular expressions.
                foreach my $type (keys %{$args->{'grep'}})
                {
                    my $greps = ref($args->{'grep'}->{$type})?$args->{'grep'}->{$type}:[$args->{'grep'}->{$type}];
                    foreach my $grep (@{$greps})
                    {
                        #print Dumper("$line ... $grep\n");
                        if ($line=~ /$grep/)
                        {
                           $file_data->{$type} .= $line;
                        }
                    }
                    
                }
            } elsif ($args->{'grep'}) {
                # Straight up regular expression array
                my $greps = ref($args->{'grep'})?$args->{'grep'}:[$args->{'grep'}];
                foreach my $grep (@{$greps})
                {
                    if ($line=~ /$grep/)
                    {
                       $file_data->{$1} .= $line;
                       
                    }
                }
            } elsif ($args->{'substr'})
            {
                my $vals = ref($args->{'substr'}->{'val'})?$args->{'substr'}->{'val'}:[$args->{'substr'}->{'val'}];

                foreach my $val (@{$vals})
                {
                   $file_data->{$val} .= ''; 
                    
                    if (substr($line,$args->{'substr'}->{'pos'},length($val)) eq $val)
                    {

                       $file_data->{$val} .= $line;
                    }
                }
            }
        }
        
        # Output file data
        foreach my $part (keys %{$file_data})
        {
            open my $fh, "> $in_file.$part" or die "Cannot write to $in_file.$part: $!";
            print $fh $file_data->{$part};
        
            $out_files[@out_files] = "$in_file.$part";    
        }
        unlink($in_file) unless ($self->{'keepSource'});
        
    }
        
    return \@out_files;
}

# Args:
#   Scalar: The Merged filename
#   Array or Arrayref: Optional
#       If an array of arrayref of filepaths is given, those will be used as source files.
#       If no optional arguments are given, the merged file will contain the contents of "filename.1", "filename.2", ... in the same directory.   
#   Returns undef if no files were found to merge, the merged filename if merging was successful.
sub merge_file($;)
{
    #print Dumper(@_);
    my $self = shift;
    my $out_file = shift;   # filepath for output file.
    
    # Arrayref of input filenames
    my $in_files;
    $in_files = (ref($_[0])?shift:\@_) if @_;

    ### Data for the merged file is here. (Buffered in memory in case of error -> no partial files)
    my $out_data='';
    

    ## If the caller provides a list of filepaths we use that.
    ## Otherwise we search for 

    unless ($in_files)
    {
        my ($name,$path) = fileparse($out_file);                # Split filepath

        opendir(DIR, $path) || die "can't opendir $path: $!";   # Read from the file dir
        my @files = grep {/$name\./}  readdir(DIR);         # find all matching subfiles
        @files = map {"$path$_"}  @files;        
        return unless (@files);                                 # Return if no files found to merge.
        $in_files = \@files;
    }


    $out_data .= $self->read_files( @{$in_files} );   
    open my $fh, "> $out_file" or warn "Cannot write to $_.$in_files: $!";
    print $fh $out_data;

    unlink(@{$in_files}) unless ($self->{'keepSource'});
    
    return $out_file
}

################### INTERNAL ##########################



# IN: Array of filepath to merge data from
sub read_files(@)
{
    my $self = shift;
    my $out_data;
    foreach ( @_ )
    {
        open my $in_fh, $_ or warn "Cannot read $_: $!";
        local $/ = undef;
        $out_data .= <$in_fh>;
    }
    $out_data;
};



1;
__END__

=head1 NAME

File::Split

=head1 SYNOPSIS

 Splits files.

 my $fs = File::Split->new({keepSource=>'1'});

 my $files_out = $fs->split_file({'parts' => 10},'filepath');

 Creates ten files named 'filepath.1','filepath.2',...,'filepath.10'.



 =head1 DESCRIPTION

File::Split defaults to removing the now-split file.

 my $fs = File::Split->new({keepSource=>'1'});

Split the file into ten equal-sized parts called filepath.1,filepath.2,...

 my $files_out = $fs->split_file({'parts' => 10},'filepath');

Split the file into multiple parts with a size of 1000 lines or less.

 my $files_out = $fs->split_file({'lines' => 1000},'filepath');

Split files into sub-sections based on a substring value. Gives filepath.MB, filepath.SK

 my $files_out = $fs->split_file({'substr'=>{pos=>'10000',val=>['MB','SK']}},'filepath');

Split file based on regular expressions grouped in a hash of arrays of regular expressions. Gives files filepath.BC, filepath.AB,...

 my $files_out = $fs->split_file({'grep'=>{
                                    'BC'=>['\t(V\d\C\d\C\d)\t'],
                                    'AB'=>['\t(T\d\C\d\C\d)\t'],
                                    'SK'=>['\t(S\d\C\d\C\d)\t'],
                                    'MB'=>['\t(R\d\C\d\C\d)\t'],
                                    'ON'=>['\t(P\d\C\d\C\d)\t','\t(N\d\C\d\C\d)\t','\t(M\d\C\d\C\d)\t','\t(L\d\C\d\C\d)\t','\t(K\d\C\d\C\d)\t'],
                                    'QC'=>['\t(G\d\C\d\C\d)\t','\t(H\d\C\d\C\d)\t','\t(J\d\C\d\C\d)\t','\t(K\d\C\d\C\d)\t','\t(S\d\C\d\C\d)\t'],
                                    'NS'=>['\t(B\d\C\d\C\d)\t'],
                                    'NB'=>['\t(E\d\C\d\C\d)\t'],
                                    'PE'=>['\t(C\d\C\d\C\d)\t'],
                                    'NL'=>['\t(A\d\C\d\C\d)\t'],
                                    'NT'=>['\t(X\d\C\d\C\d)\t'],
                                    'NU'=>[],
                                    'YT'=>['\t(Y\d\C\d\C\d)\t'],
                                        }
                                },'dat/zip411Bus040710.TXT');


Split file on array of regular expressions. filename extensions are based on the matched value.

 $files_out = $fs->split_file({'grep'=>['\t(MB)\t','\t(SK)\t','\t(NB)\t','\t(NL)\t','\t(NT)\t','\t(NS)\t','\t(YT)\t','\t(PE)\t','\t(NU)\t','\t(BC)\t','\t(ON)\t','\t(AB)\t','\t(QC)\t']},'dat/zip411Bus041013.TXT');

Merge any file that matches 'filepath_for_reconstructed_file*'

 my $out_name = $fs->merge_file('filepath_for_reconstructed_file');

 
=head1 CAVEATS

This script isn't fully mature, and interfaces may change. 

File::Split will create empty files if you split an empty file. If you request five parts, you will receive five parts.

File::Split will return undef if you try to split a non-existant file.

 
=head1 AUTHOR

Phil Middleton


