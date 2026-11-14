/* main.c — showcase 4.5.3–5 host acceptance: wire records and wheel wrapping. */
#include "records.h"
#include "protocol.h"
#include "virtual_input.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static uint8_t response[1024], previous_response[1024];
static unsigned response_bytes,completed,reserved,replies;
static unsigned reserve(unsigned kind,uint32_t total,uint32_t *base)
{ reserved=kind; *base=0x100; return total>1024 ? 3 : 0; }
static unsigned complete(unsigned kind,uint32_t base,uint32_t bytes,uint32_t *index)
{ if(kind==1 || kind==2) return EDSC_PENDING;
  assert(kind==3 && base==0x100 && bytes==128); completed++; *index=30; return 0; }
static uint8_t current[56]={1,2};
static unsigned command_result, cancelled;
static void state(uint8_t p[56]) { memcpy(p,current,56); }
static unsigned command(unsigned type,const uint8_t *p,unsigned n,uint32_t seq)
{ (void)type; (void)p; (void)n; (void)seq; return command_result; }
static unsigned progress(unsigned type) { (void)type; return command_result; }
static void cancel(unsigned kind) { assert(kind==2); ++cancelled; }
static void reply(const uint8_t *d,unsigned n)
{ memcpy(previous_response,response,response_bytes);
  memcpy(response,d,n); response_bytes=n; ++replies; }
static void message(struct edsc *s,unsigned type,const uint8_t *p,unsigned n)
{
    uint8_t d[1024]={0}; memcpy(d,"EDSC",4); d[4]=(uint8_t)type;
    d[6]=(uint8_t)n; d[7]=(uint8_t)(n>>8); record_put32(d+8,0x12345678);
    memcpy(d+12,p,n); edsc_message(s,d,n+12);
}
int main(int argc,char **argv)
{
    struct edsc s={.ops={reserve,complete,reply,state,command,progress,cancel},.build="abc123"};
    uint8_t connect=0; edsc_message(&s,&connect,1);
    assert(response[4]==0x88 && response_bytes==116);
    assert(previous_response[4]==0x84 && record_u16(previous_response+12)==3);
    assert(!memcmp(previous_response+16,"abc123",6) && previous_response[32]==1);
    edsc_poll(&s,100,100); assert(response[4]==0x85 && response_bytes==68);
    assert(!memcmp(response+12,current,56));
    uint8_t chain[100]={1,0,255,0};
    edsc_chain_snapshot(&s,7,chain); edsc_poll(&s,101,100);
    assert(response[4]==0x88 && record_u32(response+12)==7 && response[16]==1);
    uint8_t stats[24]={0};
    edsc_pipe_stats(&s,stats,sizeof stats,100,100);
    assert(response[4]==0x89 && response_bytes==36);
    unsigned stats_replies=replies;
    edsc_pipe_stats(&s,stats,sizeof stats,199,100); assert(replies==stats_replies);
    current[0]=4; edsc_pipe_stats(&s,stats,sizeof stats,200,100);
    assert(replies==stats_replies); current[0]=1;
    unsigned before=replies; edsc_poll(&s,199,100); assert(replies==before);
    current[3]=1; edsc_poll(&s,199,100); assert(replies==before+1);
    edsc_poll(&s,299,100); assert(replies==before+2);
    uint8_t p[1012]={3,0,0,0,128};
    message(&s,1,p,8); assert(reserved==3 && response[4]==0x81);
    assert(response_bytes==16 && record_u32(response+8)==0x12345678);
    edsc_bulk(&s,127); assert(response[4]==0x82 && response[13]==1 && !completed);
    message(&s,1,p,8); edsc_bulk(&s,128);
    assert(!response[13] && record_u32(response+16)==30 && completed==1);
    record_put32(p+4,1025); message(&s,1,p,8); assert(response[13]==3);
    p[0]=7; message(&s,1,p,8); assert(response[13]==2);
    message(&s,2,p,0); assert(response[4]==0x82 && response[13]==2);
    for(unsigned i=0;i<1000;++i) p[i]=(uint8_t)i;
    message(&s,3,p,1000); assert(response[4]==0x83 && response_bytes==1012);
    assert(!memcmp(p,response+12,1000));
    message(&s,3,p,1001); assert(response[4]==0x82 && response[13]==2);
    memset(p,0,sizeof p); p[0]=1; record_put32(p+4,16); message(&s,1,p,8);
    p[0]=3; record_put32(p+4,128); message(&s,1,p,8);
    assert(response[13]==3 && s.kind==1 && s.total==16);
    before=replies; edsc_bulk(&s,16); assert(replies==before && s.active);
    s.seq=77; edsc_finish(&s,1,0);
    assert(response[12]==1 && response[13]==0 && !s.active);
    assert(record_u32(response+8)==0x12345678);
    uint8_t bad[12]={0}; edsc_message(&s,bad,12); assert(response[13]==2);
    message(&s,1,p,7); assert(response[13]==1);
    memset(p,0,sizeof p); p[0]=1;
    command_result=EDSC_PENDING; before=replies; message(&s,4,p,4);
    assert(replies==before+1 && response[14]==1);
    command_result=0; edsc_poll(&s,300,100); assert(response[14]==2);
    command_result=EDSC_PENDING; message(&s,4,p,4);
    command_result=4; edsc_poll(&s,301,100); assert(response[14]==3 && response[15]==4);
    message(&s,4,p,3); assert(response[14]==3 && response[15]==1);
    p[0]=7; message(&s,4,p,4); assert(response[15]==2);
    p[0]=5; p[1]=1; message(&s,4,p,4); assert(response[15]==5);
    memset(p,0,sizeof p); p[0]=1; p[2]=2; p[4]=4; memcpy(p+8,"a.jpg",4);
    command_result=0; message(&s,5,p,12); assert(response[14]==2);
    message(&s,5,p,11); assert(response[15]==1);
    p[8]='/'; message(&s,5,p,12); assert(response[15]==2);
    message(&s,6,p,24); assert(response[4]==0x82 && response[13]==2);
    memset(p,0,sizeof p); message(&s,9,p,99); assert(response[15]==1);
    message(&s,9,p,100); assert(response[14]==2);
    message(&s,10,p,4); assert(response[15]==2);
    p[0]=1; message(&s,10,p,4); assert(response[14]==2);
    p[1]=1; message(&s,10,p,4); assert(response[15]==2);
    memset(p,0,sizeof p); p[0]=50; message(&s,7,p,16); assert(response[14]==2);
    command_result=EDSC_PENDING; message(&s,7,p,16);
    command_result=0; edsc_poll(&s,303,100); assert(response[14]==2 && response[12]==7);
    message(&s,7,p,15); assert(response[15]==1);
    p[0]=24; message(&s,7,p,16); assert(response[15]==2);
    memset(p,0,sizeof p); p[0]=2; record_put32(p+4,16);
    current[0]=1; s.chain[0]=0; message(&s,1,p,8); assert(response[13]==5);
    current[0]=1; s.chain[0]=1; s.image_info=0; message(&s,1,p,8); assert(response[13]==5);
    const uint8_t info[9]={1,0,1,0,1,0,0,0,'x'};
    message(&s,5,info,9); assert(response[14]==2);
    message(&s,1,p,8); assert(s.active);
    edsc_bulk(&s,16); assert(s.active);
    s.bulk_seq=0xabcdef12;
    before=replies; message(&s,8,p,0);
    assert(!s.active && cancelled==1 && replies==before+2 && response[14]==2);
    assert(previous_response[4]==0x82 && previous_response[13]==6);
    assert(record_u32(previous_response+8)==0xabcdef12);
    assert(record_u32(response+8)==0x12345678);
    before=replies; edsc_finish(&s,2,42); assert(replies==before);
    message(&s,8,p,0); assert(replies==before+1 && cancelled==1);
    message(&s,8,p,1); assert(response[15]==1);
    edsc_image_step(&s,-1); assert(response[4]==0x87 && response[12]==255);
    uint8_t d[128]={0}; memcpy(d,"EDG2",4); d[4]=2; record_put32(d+8,128);
    d[12]=2; d[14]=2; record_put32(d+16,100); record_put32(d+28,104);
    record_put32(d+32,24); memcpy(d+36,"test",5);
    struct game_record r; assert(!game_record_parse(&r,d,sizeof(d)));
    assert(r.name==d+100 && r.rom==d+104 && !r.cover);
    record_put32(d+28,126); assert(game_record_parse(&r,d,sizeof(d))==2);
    record_put32(d+28,104); record_put32(d+24,124); d[20]=120; d[22]=160;
    assert(game_record_parse(&r,d,sizeof(d))==2); record_put32(d+24,0);
    uint8_t pack[140]={0}; memcpy(pack,"EDGP",4); pack[4]=2; pack[6]=1;
    record_put32(pack+8,12); memcpy(pack+12,d,128); unsigned count;
    assert(!game_pack_count(pack,sizeof(pack),&count) && count==1);
    assert(!game_pack_record(&r,pack,sizeof(pack),0));
    pack[4]=1; assert(game_pack_count(pack,sizeof(pack),&count)==2);
    uint8_t frame[8]={0}; frame[7]=126; virtual_input_network(frame);
    assert(virtual_input_take_wheel()==126);
    frame[7]=254; virtual_input_network(frame); assert(virtual_input_take_wheel()==-128);
    frame[7]=2; virtual_input_network(frame); assert(virtual_input_take_wheel()==4);
    frame[7]=0; virtual_input_network(frame); assert(virtual_input_take_wheel()==-2);
    frame[7]=3; virtual_input_network(frame); frame[7]=9; virtual_input_network(frame);
    assert(virtual_input_take_wheel()==9 && virtual_input_take_wheel()==0);
    if(argc==2) {
        FILE *file=fopen(argv[1],"rb"); assert(file);
        assert(!fseek(file,0,SEEK_END)); long bytes=ftell(file); assert(bytes>0);
        rewind(file); uint8_t *data=malloc((size_t)bytes); assert(data);
        assert(fread(data,1,(size_t)bytes,file)==(size_t)bytes); fclose(file);
        assert(!game_pack_count(data,(uint32_t)bytes,&count) && count==30);
        for(unsigned i=0;i<count;++i) assert(!game_pack_record(&r,data,(uint32_t)bytes,i));
        printf("PASS real EDGP: %u games, %ld bytes\n",count,bytes); free(data);
    }
    puts("PASS EDSC v3 HELLO/STATE/APP/IMAGE_INFO/CHAIN/PRESET/DETECT/CANCEL/ACK, records and wheel");
}
