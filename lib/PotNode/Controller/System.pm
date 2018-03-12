package PotNode::Controller::System;
use Mojo::Base 'Mojolicious::Controller';
use PotNode::QRCode;
use Mojo::URL;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::IOLoop;
use Mojo::UserAgent;
use Mojo::ByteStream 'b';
use Data::UUID;

# This action will render a template

  my $ua = Mojo::UserAgent->new;

sub start {
    my $c = shift;
#    my $ua  = Mojo::UserAgent->new;
    my $url = $c->param('html') || "index";
	$url = 'http://127.0.0.1:8080/ipfs/QmX2We6Gcf9sBVcjLBHqPjUQjQuvA4UhqwSuyqvYSQfuyj/'.$url.'.html';
	$c->app->log->debug("URL : $url");
#	my $html = $ua->get('http://127.0.0.1:8080/ipfs/QmfQMb2jjboKYkk5f1DhmGXyxcwNtnFJzvj92WxLJjJjcS')->res->dom->find('section')->first;

	my $html = $ua->get($url)->res->dom->find('div.container')->first;
	#b('foobarbaz')->b64_encode('')->say;
	my $encodedfile = b($html);
	$c->app->log->debug("Encoded File : $encodedfile");
    $c->stash(import_ref => $encodedfile);
    
    $c->render(template => 'system/start');
};


sub check {
    my $redis = Mojo::Redis2->new;
    my $c = shift;
    my $path = "/home/node/.multichain/";
    my $process_chk_command;
    my $command;
    $c->app->log->debug("Recurring : Checking");
    
    if (!$redis->exists("checkprocess")){
        $redis->setex('checkprocess',30, "yes");
        my @dir_list = grep { /^\w{32}$/ } glob "$path*";
        my $dircount = @dir_list;
        $c->app->log->debug("Directories : $dircount");
        ## Checks the multichain directory for any active blockchains and checks if the daemon is running
        if ($dircount > 0) {
            opendir( my $DIR, $path );
            while ( my $entry = readdir $DIR ) {
                ## Finds all directories and filters out all directories apart from those that contain HEX 32 chars
                next unless -d $path . '/' . $entry;
                next if $entry eq '.' or $entry eq '..';
                next if $entry !~ m/^\w{32}$/;
                if ( -f '/home/node/run/'.$entry.'.pid') {
                    $c->app->log->debug("Running Process : $entry");
                } else {
                    ## launched the daemon using > /dev/null & to return control to mojolicious
                    $command = "multichaind $entry -daemon -pid=/home/node/run/$entry.pid > /dev/null &";
                    system($command);
                    $c->app->log->debug("Starting : $entry");
                }
            }
            
            closedir $DIR;
        } else {
            $command = 'ipfs add -r -w -Q /home/node/pot_node';
            my $value = qx/$command/;
            $value =~ s/\R//g;
            $c->app->log->debug("No Directories - Hash : $value");
            my $idinfo = $ua->get("http://127.0.0.1:5001/api/v0/id")->result->json;
            my @scanNetwork;
            my $network;
            $c->render_later;
            $ua->get("http://127.0.0.1:5001/api/v0/dht/findprovs?arg=$value&num-providers=3" => sub {
                my ($self, $tx) = @_;
                $c->app->log->debug("Starting");
                $network = $tx->result->body;            
                my @ans = split(/\n/, $network);

                foreach my $line ( @ans ) {
                    my $data = decode_json($line);
                    if ($data->{'Type'} eq '4') {
                            my $values = $data->{'Responses'}->[0];
                            if ($values->{'ID'} ne $idinfo->{'ID'}) {
                                    foreach my $address ( @{$values->{'Addrs'}} ) {
                                            my ($junk,$proto,$address,$trans,$port) = split('/', $address);
                                            ## TODO : Add Support for IPv6
                                            if ($proto eq 'ip4') {
                                                    if ($address ne '127.0.0.1') {
                                                            ## Only Add $address to Array if grep cannot find the address in the array
                                                            $address = "http://$address/node/alive";
                                                            $c->app->log->debug("Adding Address : $address");
                                                            push(@scanNetwork, $address) if ( ! grep(/^$address$/, @scanNetwork));
                                                    }
                                            }

                                    }
                            }
                    }
                }
                
                $c->app->log->debug("Testing URLs");
                
#               start_urls($ua, \@scanNetwork, \&get_callback);

                $c->render_later;
                my $delay = Mojo::IOLoop->delay;
                $delay->on(finish => sub{
                    my $delay = shift;
                    $c->app->log->debug("Scan Finished");
                    $c->render_dumper($_);
                });
                $ua->get( $_ => $delay->begin ) for @scanNetwork;

                
            });
        }
        
        if (!$redis->exists("addpotnode")){
            $command = 'ipfs add -r -w -Q /home/node/pot_node';
            my $value = qx/$command/;
            $value =~ s/\R//g;
            $c->app->log->debug("pot_node Hash : $value");
            #my $res = $ua->get("http://127.0.0.1:5001/api/v0/pubsub/sub?arg=$value&discover=\1");
            #$self->app->dumper($res);
            $redis->setex('addpotnode',30, "yes");
        }

        $redis->del("checkprocess");
    }
    
    if (!$redis->exists("myipfsid")){
        my $idinfo = $ua->get("http://127.0.0.1:5001/api/v0/id")->result->json;
        $c->app->log->debug("IPFS ID : $idinfo->{ID}");
        $redis->set(myipfsid => encode_json($idinfo));
    }
    $c->render(text => 'Ok', status => 200);
};


sub upload {
    my $c = shift;
#    my $ua  = Mojo::UserAgent->new;
#       my $html = $ua->get('http://127.0.0.1:8080/ipfs/QmfQMb2jjboKYkk5f1DhmGXyxcwNtnFJzvj92WxLJjJjcS')->res->dom->find('section')->first;
        my $html = $ua->get('http://127.0.0.1:8080/ipfs/Qmbb28sUkFdGz3YxquVkXbE2CrWBFBceJyKYa1ms1W48do')->res->body;
        #b('foobarbaz')->b64_encode('')->say;
        my $encodedfile = b($html);
        $c->app->log->debug("Encoded File : $encodedfile");
    $c->stash(import_ref => $encodedfile);

    $c->render(template => 'system/start');
};

sub createchain {
    my $c = shift;
 #   my $ua  = Mojo::UserAgent->new;
    
    if ($c->req->method('GET')) {
        $c->render(template => 'system/createchain');
    }
    
    if ($c->req->method('POST')) {
        my $ug = Data::UUID->new;
        my $uuid = $ug->to_string($ug->create());
        $uuid =~ s/-//g;
        my $param = $c->req->params->to_hash;
        say $c->app->dumper($param);
        my @optionlist;
        push (@optionlist,"-chain-description=$param->{'name'}") if $param->{'name'};
        push (@optionlist,"-anyone-can-connect=true") if $param->{'public'};
        push (@optionlist,"-anyone-can-send=true,anyone-can-receive=true") if $param->{'sr'};
        my $options = join(' ', @optionlist);
        $c->app->log->debug("Options : $options");
        
        my $command = "/usr/local/bin/multichain-util create $uuid $options";
        my $create = qx/$command/;
        $c->app->log->debug("Create : $create");
        
    }
    
    
};


sub genqrcode {
    ## Generates QRCode
    ## 38mm Label needs size 3 Version 5 (default)
    ## 62mm With Text size 4 Version 5
    ## 62mm No Text size 5 60mmX60mm Version 5
    my $c = shift;
    #my $ua  = Mojo::UserAgent->new;
    my $ug = Data::UUID->new;
    my $uuid = $ug->create();
    $uuid = $ug->to_string( $uuid );
    my $text = $c->param('text') || "container/$uuid";
    my $size = $c->param('s') || 3; 
    my $version = $c->param('v') || 5;
    my $blank = $c->param('b') || 'n';
    print "Text : $text\n";
    if ($blank ne 'y') {
            $text = 'https://pot.ec/'.$text;
    }       
    my $mqr  = Api::QRCode->new(
    text   => $text,
    qrcode => {size => $size,margin => 2,version => $version,level => 'H'}
    );
    my $logo = Imager->new(file => "public/images/potlogoqrtag.png") || die Imager->errstr;
    $mqr->logo($logo);
    $mqr->to_png("public/images/$uuid.png");
    
    if (defined($c->param('hash'))) {
            print "Hash\n";
            my $result = $ua->post('http://127.0.0.1:5001/api/v0/add' => form => {image => {file => "public/images/$uuid.png",'Content-Type' => 'application/octet-stream'}})->result->json;
            unlink "public/images/$uuid.png";
            $c->render(json => $result,status => 200);
    } else {
            print "Text\n";
            my $file = Mojo::Asset::File->new(path => "public/images/$uuid.png");
            $file = $file->slurp;
            unlink "public/images/$uuid.png";
            $c->render(data => $file,format => 'png',status => 200);
    }       
        
};


sub genqrcode64 {
    ## Generates QRCode
    ## 38mm Label needs size 3 Version 5 (default)
    ## 62mm With Text size 4 Version 5
    ## 62mm No Text size 5 60mmX60mm Version 5
    my $c = shift;
    my $text = $c->param('text');
    my $size = $c->param('s') || 3;
    my $version = $c->param('v') || 5;
    my $blank = $c->param('b') || 'no';
    if ($blank eq 'no') {
            $text = 'https://pot.ec/'.$text;
    }
    my $mqr  = Api::QRCode->new(
    text   => $text,
    qrcode => {size => $size,margin => 2,version => $version,level => 'H'}
    );
    my $logo = Imager->new(file => "public/appimages/potlogolarge.png") || die Imager->errstr;
    $mqr->logo($logo);
    $mqr->to_png_base64("public/images/test.png");

    $c->render(json => {'message' => 'Ok','image' => $mqr->to_png_base64("public/images/test.png")},status => 200);
}


sub start_urls {
    my ($ua, $queue, $cb) = @_;

    
    # Limit parallel connections to 4
    state $idle = 4;
    state $delay = Mojo::IOLoop->delay(
        sub{
            say @$queue ? "Loop ended before queue depleated" : "Finished"
        }
    );

  while ( $idle and my $url = shift @$queue ) {
    $idle--;
    
    $ua->app->log->debug("Starting $url, $idle idle");
    
    $delay->begin;

    $ua->get($url => sub{
      $idle++;
      $ua->app->log->debug("Got $url, $idle idle");
      $cb->(@_, $queue);

      # refresh worker pool
      start_urls($ua, $queue, $cb);
      $delay->wait;
    });

  }

  # Start event loop if necessary
  $delay->wait unless $delay->ioloop->is_running;
}

sub get_callback {
    my ($ua, $tx, $queue) = @_;

    # Parse only OK HTML responses

    return unless
        $tx->res->is_success;

    # Request URL
    my $url = $tx->req->url;
    say "Processing $url";
    parse_html($url, $tx, $queue);
}

sub parse_html {
    my ($url, $tx, $queue) = @_;

    print Dumper($tx);

    say '';

    return;
}


1;
