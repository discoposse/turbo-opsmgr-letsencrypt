# Why
Encryption is important. That's why the Turbonomic Operations Manager (opsmgr) ships with a self signed SSL certificate.

Of course, there are downsides to this. First the provided certificate will eventually expire. Perhaps more vexing tho is that you get the dreaded "insecure" warning whenever you first visit a newly launched Turbonomic instance.

![Insecure Warning](https://github.com/turbonomiclabs/turbo-opsmgr-letsencrypt/raw/master/img/insecure.png)

To avoid this, you'll want to get a certificate which actually matches the hostname of your Turbonomic instance. You can go about this by getting a certificate signed by a well known Certificate Authority (CA), and there is excellent documentation on configuring that [here](https://greencircle.vmturbo.com/docs/DOC-4630-enforcing-secure-access-for-turbonomic-centos-7).

But there is another, free and open option.

# What
[Let's Encrypt](https://letsencrypt.org/) is a free and open certificate authority where you can programmatically request a new SSL certificate for your FQDN.

This script automates the process of fetching (and renewing) a certificate from Let's Encrypt and configuring the opsmgr to use that new, fully legit SSL certificate.

# How
So how should you use this script?

There are some prerequisites, and it's useful to have a highlevel understanding of how Let's Encrypt works, so that you can better understand what this script is doing.

## Let's Encrypt
Let's Encrypt has a public API where you can request a new certificate, or renew an existing one. You need to provide an email address which Let's Encrypt will use for important notifications, such as a certificate expiring. You will also need to accept the [terms of service](https://letsencrypt.org/repository/) from Let's Encrypt.

When you make a request to Let's Encrypt, their automated system must validate that you have administrative control over the domain you're requesting a certificate for. Let's Encrypt supports several different methods for that, but this script utilizes the HTTP challenge mechanism. Basically, Let's Encrypt will make an HTTP request to your server, using the domain/hostname specified for the certificate. That HTTP request must respond with a token that was part of the response to the request for a new or renewed certificate.

Don't worry, all of this happens automatically when using the script. It is important to note that this script assumes your opsmgr is accessible from the public internet, using the domain/hostname for which you're requesting a certificate.

## Prerequisites
This script effectively has only one prereq, namely that you have a DNS record setup which points to your (public internet facing) opsmgr.

Once you've made the necessary DNS record, you can verify it with a simple `dig` or `nslookup`. You can even use a web based tool like [this](http://www.kloth.net/services/nslookup.php).

Enter the FQDN you want a certificate for, and make sure that the response is the public IP of your opsmgr.

```
$ dig opsmgr.ryangeyer.com

; <<>> DiG 9.10.6 <<>> opsmgr.ryangeyer.com
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 39049
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 512
;; QUESTION SECTION:
;opsmgr.ryangeyer.com.		IN	A

;; ANSWER SECTION:
opsmgr.ryangeyer.com.	300	IN	A	1.1.1.1

;; Query time: 54 msec
;; SERVER: 192.168.1.1#53(192.168.1.1)
;; WHEN: Fri Jun 28 11:00:14 PDT 2019
;; MSG SIZE  rcvd: 65
```

## Usage
Now all you need to do is run the script, and the rest happens automagically.

The script accepts two inputs.

* `-e|--email`: Your email address, used by Let's Encrypt for renewal or other administrative communications.
* `-h|--fqdn`: The fully qualified domain name of your Turbonomic opsmgr

Remember, the script will automatically accept the Let's Encrypt Terms of Service for you, so make sure you've read them [here]((https://letsencrypt.org/repository/)).

Due to potential conflicts of dependencies on the opsmgr, the script installs and uses Docker for parts of the communication to the Let's Encrypt API. Specifically, the Let's Encrypt [certbot](https://hub.docker.com/r/certbot/certbot/) is run in a Docker container.

So, the script does the following things.

* Install Docker, start the docker daemon, and configure docker daemon to start automatically
* Creates `/etc/httpd/conf.d/00letsencrypt.conf` which includes Apache rules to forward the Let's Encrypt challenge requests to the certbot container
* Requests a new certificate (with 4096 bit rsa encryption) for the given FQDN
* Moves `/etc/httpd/conf.d/ssl.conf` to `/etc/httpd/conf.d/ssl.conf.turbo`
* Creates a new `/etc/httpd/conf.d/ssl.conf` which uses the newly created certificate
* Creates a cron job which runs twice a day to renew the certificate if it is about to expire

# Encrypt all the things
So that's it! With this simple script, you can very easily configure your opsmgr to be encrypted with a trusted CA, eliminating the security warning message.

This has been tested on the Turbonomic opsmgr distributed as an `*.ova` for vCenter, as well as the offerings in the Microsoft Azure and AWS marketplaces respectively. It *should* work on any CentOS 7 based Turbonomic opsmgr, but feel free to provide feedback if you encounter issues.
