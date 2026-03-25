//
//  TLSServer.mm
//  mTLSServer
//
//  Created by Arjun Radhakrishnan on 12/15/23.
//

#import "TLSServer.h"
#import "opensslv.h"
#include <errno.h>
#include <unistd.h>
#include <string.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <resolv.h>
#include "ssl.h"
#include "err.h"
#include <vector>
#include <string>
#include "x509.h"
#include "stack.h"


using namespace std;
#define FAIL    -1

int openListener(int port)
{   int sd;
    struct sockaddr_in addr;
    
    sd = socket(PF_INET, SOCK_STREAM, 0);
    bzero(&addr, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    addr.sin_addr.s_addr = INADDR_ANY;
    if ( ::bind(sd, (struct sockaddr*)&addr, sizeof(addr)) != 0 )
    {
        perror("can't bind port");
        abort();
    }
    if (listen(sd, 10) != 0 )
    {
        perror("Can't configure listening port");
        abort();
    }
    return sd;
}

SSL_CTX* initServerContext(void)
{
    const SSL_METHOD *method;
    SSL_CTX *ctx;
    
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();
    
    method = TLS_server_method();
    ctx = SSL_CTX_new(method);
    if(ctx == NULL)
    {
        ERR_print_errors_fp(stderr);
        abort();
    }
    
    SSL_CTX_set_cipher_list(ctx, "ALL:eNULL");
    
    return ctx;
}

void loadCertificates(SSL_CTX* ctx, const char* CertFile,const char* KeyFile, vector<string> caFiles)
{
    if (SSL_CTX_load_verify_locations(ctx, CertFile, KeyFile) != 1)
    {
        ERR_print_errors_fp(stderr);
    }
    // server cert
    if (SSL_CTX_use_certificate_file(ctx, CertFile, SSL_FILETYPE_PEM) <= 0)
    {
        ERR_print_errors_fp(stderr);
        abort();
    }
    
    // server private key
    if (SSL_CTX_use_PrivateKey_file(ctx, KeyFile, SSL_FILETYPE_PEM) <= 0)
    {
        ERR_print_errors_fp(stderr);
        abort();
    }
    // verify server private key
    if (!SSL_CTX_check_private_key(ctx))
    {
        fprintf(stderr, "Private key does not match the public certificate\n");
        abort();
    }
    
    // mTLS options
    SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT, NULL);
    
    for (string cafile : caFiles)
    {
        const char* filePath = cafile.c_str();
        SSL_CTX_load_verify_locations(ctx,filePath,NULL);
        X509* cert = X509_new();
        BIO* bio_cert = BIO_new_file(filePath, "rb");
        PEM_read_bio_X509(bio_cert, &cert, NULL, NULL);
        SSL_CTX_add_client_CA(ctx, cert);
    }
    
    const struct stack_st_X509_NAME *st = SSL_CTX_get_client_CA_list(ctx);
    int count = OPENSSL_sk_num((const OPENSSL_STACK *)st);
    printf("Trusted CA's for client cert verification:  %d\n",count);
}

void showCerts(SSL* ssl)
{
    X509 *cert;
    char *line;
    
    cert = SSL_get_peer_certificate(ssl);
    if ( cert != NULL )
    {
        printf("Server certificates:\n");
        line = X509_NAME_oneline(X509_get_subject_name(cert), 0, 0);
        printf("Subject: %s\n", line);
        free(line);
        line = X509_NAME_oneline(X509_get_issuer_name(cert), 0, 0);
        printf("Issuer: %s\n", line);
        free(line);
        X509_free(cert);
    }
    else
    {
        printf("No certificates.\n");
    }
}

void handleConnection(SSL* ssl)
{
    if ( SSL_accept(ssl) == FAIL)
    {
        ERR_print_errors_fp(stderr);
    }
    else
    {
        while (true)
        {
            char buff[1024];
            memset(buff,0,1024);
            int bytes = SSL_read(ssl, buff, sizeof(buff)); /* get request */
            if ( bytes > 0 )
            {
                printf("Received - %s", buff);
                char reply[2048];
                memset(reply,0,2048);
                int replySize = snprintf(reply,2048,"echo: %s", buff);
                int sent = SSL_write(ssl, reply, replySize); /* send reply */
                if (sent <= 0) {
                    break;
                }
            }
            else
            {
                break;
            }
        }
    }
    
    int sd = SSL_get_fd(ssl);
    SSL_free(ssl);
    close(sd);
}

@interface TLSServer()
{
    SSL_CTX *ctx;
}

@property (nonatomic) int server;
@end

@implementation TLSServer

-(void)start
{
    char portnum[]="8895";
    
    const char *cert_path = [[[NSBundle mainBundle] pathForResource:@"server-cert" ofType:@"pem"] cStringUsingEncoding:NSUTF8StringEncoding];
    const char *key_path = [[[NSBundle mainBundle] pathForResource:@"server-key" ofType:@"pem"] cStringUsingEncoding:NSUTF8StringEncoding];
    const char *ca1_path = [[[NSBundle mainBundle] pathForResource:@"ca1-cert" ofType:@"pem"] cStringUsingEncoding:NSUTF8StringEncoding];
    const char *ca2_path = [[[NSBundle mainBundle] pathForResource:@"ca2-cert" ofType:@"pem"] cStringUsingEncoding:NSUTF8StringEncoding];
    
    vector<string> caFiles;
    string ca1_str(ca1_path);
    caFiles.push_back(ca1_str);
    
    string ca2_str(ca2_path);
    caFiles.push_back(ca2_str);
    
    
    SSL_library_init();
    
    ctx = initServerContext();
    loadCertificates(ctx, cert_path, key_path,caFiles);
    self.server = openListener(atoi(portnum));
    
    while (1)
    {
        struct sockaddr_in addr;
        socklen_t len = sizeof(addr);
        SSL *ssl;
        int client = accept(self.server, (struct sockaddr*)&addr, &len);
        printf("mTLS Connection: %s:%d\n",inet_ntoa(addr.sin_addr), ntohs(addr.sin_port));
        ssl = SSL_new(ctx);
        SSL_set_fd(ssl, client);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
            handleConnection(ssl);
        });
    }
}

-(void)stop
{
    close(self.server);
    SSL_CTX_free(ctx);
}
@end
