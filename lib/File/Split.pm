package File::Split;

use Data::Dumper;
use File::Basename;

use strict;
use warnings;


our $VERSION = '0.25';

sub new {
    my $class   = shift;
    my %args = ref($_[0])?%{$_[0]}:@_;
    my $self = \%args;


    bless $self, $class;
    return $self;
};


# Splits a file into an arbitrary number of parts. split_file({'parts'}=>'10',filepath)
# Dies if it can't read or write a file.
# Returns an arrayref of split filepaths

# I you want to match regular expressions
#   you call it like this:
#   split_file(grep=>{'\t(AB)\t','\t(BC)\t',...,...},filepath)
# and the file will be split into subfiles like this:
#   filepath.AB
#   filepath.BC
sub split_file
{
    my $self = shift;
    my $args = shift;          ### how many parts to split
    my @in_files = @_;           ### the files to split
    
    my @out_files;          ### Array of filenames that were generated.
    
    
        
    foreach my $in_file( @in_files ) 
    {
        if ($args->{'parts'})
        {
            # Get filedata (could be improved by streaming, but it isn't).
            # All I need is a better way to count the number of lines in a file.
            open my $in_fh, $in_file or die "Cannot read $in_file: $!";
            my @out_data = <$in_fh>;   
            close $in_fh;
            
            my $parts = $args->{'parts'};
            my $size = @out_data / $parts;
            #print "Size $size\nParts $parts\n";
            my $x =-1;
            while ($x++ < $parts-1)
            {
                my $out_file = "$in_file.".($x+1);
                my @out_data_slice = @out_data[($x*$size)..(($x*$size)+($size-1))];
                my $out_data_str = join('',@out_data_slice);
                open my $fh, "> $out_file" or warn "Cannot write to $out_file: $!";
                print $fh $out_data_str;
                
            }
                my $out_file = "$in_file.$parts";
                my @out_data_slice = @out_data[($parts-1)*$size..(@out_data-1)];
                my $out_data_str = join('',@out_data_slice);
                open my $fh, "> $out_file" or warn "Cannot write to $out_file: $!";
                print $fh $out_data_str;
            

        } elsif ($args->{'bin-parts'})
        {
            
            my $parts = $args->{'bin-parts'};
            my $size = (-s $in_file) / $parts;   ### how big should the new file be?
    
            ### open the input file
            open my $in_fh, $in_file or die "Cannot read $in_file: $!";
            binmode $in_fh;
        
            ### for all but the last part, read the amount of data, then write it to the appropriate output file.
            for my $part (1 .. $parts - 1) {
        
                ### read an output file worth of data
                read $in_fh, my $buffer, $size or warn "Read zero bytes from $in_file: $!";
        
                ### write the output file
                open my $fh, "> $in_file.$part" or die "Cannot write to $in_file.$part: $!";
    
                ### Track generated files.
                $out_files[@out_files] = "$in_file.$part";    
    
                print $fh $buffer;
            }
        
            # for the last part, read the rest of the file. Buffer will shrink to the actual bytes read.
            read $in_fh, my $buffer, (-s $in_file) or warn "Read zero bytes from $in_file: $!";
            open my $fh, "> $in_file.$parts" or die "Cannot write to $in_file.$parts: $!";
            $out_files[@out_files] = "$in_file.$parts";    ### Track generated files.
            print $fh $buffer;
            
            unlink($in_file) unless ($self->{'keepSource'});
        } 
        elsif($args->{'grep'}||$args->{'substr'}) 
        {
            my $file_data;  # The lines will go in here.
            
            open my $in_fh, $in_file or die "Cannot read $in_file: $!";
            binmode $in_fh;
            while (<$in_fh>)
            {
                my $line = $_;
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
                    my $vals = ref($args->{'val'})?$args->{'val'}:[$args->{'val'}];
                    print "Next line:$_\n";
                    foreach my $val (@{$vals})
                    {
                        if (substr($_,$args->{'pos'},length($val)) eq $val)
                        {
                           $file_data->{$val} .= $_;
                        }
                    }
                }
            }
            
            # Output file data
            foreach my $part (keys %{$file_data})
            {
                print Dumper(keys %{$file_data});
                print $part;
                open my $fh, "> $in_file.$part" or die "Cannot write to $in_file.$part: $!";
                print $fh $file_data->{$part};
            
                $out_files[@out_files] = "$in_file.$part";    
            }
        }
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
    print Dumper(@_);
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
        #print Dumper(@files);
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

FILE::SPLIT

=head1 SYNOPSIS

 Splits files.

 my $fs = File::Split->new({keepSource=>'1'});

 my $files_out = $fs->split_file({'parts' => 10},'filepath');

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

=head1 AUTHOR

Phil Middleton


