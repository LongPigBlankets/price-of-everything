// DRAFT widget compute core: ridge-skeleton hill field (SkeletonRelief synthesis).
// Runs in a browser canvas widget. Reviewed before embedding.
// Conventions: game units; flat-top hexes w540 h480; 6 absolute thresholds.
(function(){
var cv=document.getElementById('cv'),ctx=cv.getContext('2d');
var W=cv.width,H=cv.height,S=0.47,OX=23,OY=25;
var HEXV=[[135,0],[405,0],[540,240],[405,480],[135,480],[0,240]];
function hexCenter(q,r){return [q*405+270, r*480+(q%2===0?0:240)+240];}
function makeHex(qr){
  var c=hexCenter(qr[0],qr[1]);
  var vs=HEXV.map(function(v){return [c[0]+v[0]-270, c[1]+v[1]-240];});
  var edges=[];
  for(var i=0;i<6;i++){
    var a=vs[i],b=vs[(i+1)%6];
    var nx=b[1]-a[1], ny=-(b[0]-a[0]); var l=Math.sqrt(nx*nx+ny*ny); nx/=l; ny/=l;
    if(nx*(a[0]-c[0])+ny*(a[1]-c[1])<0){nx=-nx;ny=-ny;}
    edges.push([a[0],a[1],nx,ny,(a[0]+b[0])/2,(a[1]+b[1])/2]);
  }
  return {c:c,edges:edges};
}
var hillHexes=[[0,0],[1,0],[2,0]].map(makeHex);
var mtnHexes=[[1,-1]].map(makeHex);
var flatHexes=[[0,1]].map(makeHex);
// Union SDFs: min of per-hex SDFs reads 0 on shared interior edges (a trench
// along every tile seam). Drop edges whose outward-nudged midpoint lands inside
// a sibling hex; the dropped-edge wedge is covered by that sibling.
function sharedMask(group){
  var keeps=[];
  for(var di=0;di<group.length;di++){var ks=[];
    for(var ei=0;ei<6;ei++){var e=group[di].edges[ei],sh=false;
      for(var dj=0;dj<group.length&&!sh;dj++){if(dj===di)continue;
        if(sdHexOne(group[dj],e[4]+e[2],e[5]+e[3])<0)sh=true;}
      ks.push(!sh);}
    keeps.push(ks);}
  return keeps;
}
function sdUnion(group,keeps,x,y){
  var m=1e9;
  for(var j=0;j<group.length;j++){var h=group[j],mm=-1e9,ks=keeps[j];
    for(var i=0;i<6;i++){if(!ks[i])continue;var e=h.edges[i];var d=(x-e[0])*e[2]+(y-e[1])*e[3];if(d>mm)mm=d;}
    if(mm<m)m=mm;}
  return m;
}
function sdHexOne(h,x,y){var m=-1e9;for(var i=0;i<6;i++){var e=h.edges[i];var d=(x-e[0])*e[2]+(y-e[1])*e[3];if(d>m)m=d;}return m;}
function sdSet(hs,x,y){var m=1e9;for(var j=0;j<hs.length;j++){var d=sdHexOne(hs[j],x,y);if(d<m)m=d;}return m;}
var domHexes=hillHexes.concat(mtnHexes);
var domKeep=sharedMask(domHexes);
var hillKeep=sharedMask(hillHexes);
var RIV=[[1245,-80],[1185,140],[1255,330],[1180,540],[1240,760],[1205,920]];
function crSample(pts,per){var out=[];for(var i=0;i<pts.length-1;i++){var p0=pts[Math.max(0,i-1)],p1=pts[i],p2=pts[i+1],p3=pts[Math.min(pts.length-1,i+2)];for(var t=0;t<per;t++){var u=t/per,u2=u*u,u3=u2*u;out.push([0.5*(2*p1[0]+(-p0[0]+p2[0])*u+(2*p0[0]-5*p1[0]+4*p2[0]-p3[0])*u2+(-p0[0]+3*p1[0]-3*p2[0]+p3[0])*u3),0.5*(2*p1[1]+(-p0[1]+p2[1])*u+(2*p0[1]-5*p1[1]+4*p2[1]-p3[1])*u2+(-p0[1]+3*p1[1]-3*p2[1]+p3[1])*u3)]);}}out.push(pts[pts.length-1]);return out;}
var rivPts=crSample(RIV,10);
function distPoly(pts,x,y){var m=1e18;for(var i=0;i<pts.length-1;i++){var ax=pts[i][0],ay=pts[i][1],bx=pts[i+1][0],by=pts[i+1][1];var dx=bx-ax,dy=by-ay;var L=dx*dx+dy*dy;var t=L?((x-ax)*dx+(y-ay)*dy)/L:0;t=t<0?0:(t>1?1:t);var ex=x-(ax+dx*t),ey=y-(ay+dy*t);var d=ex*ex+ey*ey;if(d<m)m=d;}return Math.sqrt(m);}
function distRiver(x,y){if(x<900)return 9999;return distPoly(rivPts,x,y);}
function mulberry32(a){return function(){a|=0;a=(a+0x6D2B79F5)|0;var t=Math.imul(a^(a>>>15),1|a);t=(t+Math.imul(t^(t>>>7),61|t))^t;return((t^(t>>>14))>>>0)/4294967296;};}
function hashN(ix,iy,s){var t=(ix*374761393+iy*668265263+s*982451653)|0;t=Math.imul(t^(t>>>13),1274126177);return((t^(t>>>16))>>>0)/4294967296;}
function sstep(x,a,b){var t=(x-a)/(b-a);t=t<0?0:(t>1?1:t);return t*t*(3-2*t);}
function noiseOct(x,y,s,f0,oct,pers){var v=0,amp=1,f=f0,tot=0;for(var o=0;o<oct;o++){var gx=x*f,gy=y*f,ix=Math.floor(gx),iy=Math.floor(gy),fx=gx-ix,fy=gy-iy,sx=fx*fx*(3-2*fx),sy=fy*fy*(3-2*fy);var a=hashN(ix,iy,s+o*77),b=hashN(ix+1,iy,s+o*77),c=hashN(ix,iy+1,s+o*77),d=hashN(ix+1,iy+1,s+o*77);var ab=a+(b-a)*sx, cd=c+(d-c)*sx;v+=amp*(ab+(cd-ab)*sy);tot+=amp;amp*=pers;f*=2;}return v/tot;}
function smax(a,b,k){var h=0.5+0.5*(b-a)/k;h=h<0?0:(h>1?1:h);return a+(b-a)*h+k*h*(1-h);}
var BANDS=['#6e8c4a','#7f944d','#94a152','#abaf5a','#c4bd65','#ddd077'];
var THR=[0.13,0.27,0.42,0.57,0.72,0.86];
var L3=THR[2];
var BLOCK_FROM=3;
var seed=1337;
var gw=(W>>1)+1, gh=(H>>1)+1;
var vGrid=new Float32Array(gw*gh);
var band=new Int8Array(W*H);
var fb=new Int16Array(W*H);
function dirTo(c,hexes,maxD){
  var best=null,bd=1e18;
  for(var i=0;i<hexes.length;i++){var mc=hexes[i].c;var dx=mc[0]-c[0],dy=mc[1]-c[1];var d=dx*dx+dy*dy;if(d<bd){bd=d;best=[dx,dy,Math.sqrt(d)];}}
  if(!best||best[2]>maxD)return null;
  return [best[0]/best[2],best[1]/best[2]];
}
function pushFromFlat(p,amt){
  var sdF=sdSet(flatHexes,p[0],p[1]);
  if(sdF>=240)return p;
  var fc=flatHexes[0].c;
  var dx=p[0]-fc[0],dy=p[1]-fc[1];var L=Math.sqrt(dx*dx+dy*dy)||1;
  return [p[0]+dx/L*(240-sdF)*amt, p[1]+dy/L*(240-sdF)*amt];
}
// skeleton state, rebuilt each compute()
var segs=[], knolls=[], sinks=[], ravine=null, skelPts=[];
function addPolySegs(pts,amp,wid){
  for(var i=0;i<pts.length-1;i++){
    var ax=pts[i][0],ay=pts[i][1],dx=pts[i+1][0]-ax,dy=pts[i+1][1]-ay;
    var LL=dx*dx+dy*dy; if(LL<1e-6)continue;
    segs.push([ax,ay,dx,dy,1/LL,amp[i],amp[i+1]-amp[i],wid[i],wid[i+1]-wid[i]]);
  }
}
function nearSkel(x,y,uptoLen,rad,ox,oy){
  // ignore skeleton within 140u of the spur's attachment point, else the
  // crest's own samples kill most spurs on their first segment
  var r2=rad*rad;
  for(var i=0;i<uptoLen;i++){
    var p=skelPts[i],ax=p[0]-ox,ay=p[1]-oy;
    if(ax*ax+ay*ay<19600)continue;
    var dx=x-p[0],dy=y-p[1];if(dx*dx+dy*dy<r2)return true;}
  return false;
}
function interpNodes(nodes,len){
  var out=new Float32Array(len);
  for(var n=0;n<nodes.length-1;n++){
    var i0=nodes[n][0],v0=nodes[n][1],i1=nodes[n+1][0],v1=nodes[n+1][1];
    for(var i=i0;i<=i1&&i<len;i++){
      var t=(i1===i0)?0:(i-i0)/(i1-i0);var tt=t*t*(3-2*t);
      out[i]=v0+(v1-v0)*tt;
    }
  }
  return out;
}
function growSpur(rnd,origin,baseAng,a0,w0,depth){
  var snapLen=skelPts.length;
  var nseg=depth===0?(3+Math.floor(rnd()*3)):(2+Math.floor(rnd()*2));
  var drift=((5+rnd()*7)*(rnd()<0.5?-1:1))*Math.PI/180;
  var pts=[origin.slice()], curAng=baseAng;
  for(var s=0;s<nseg;s++){
    if(s>0)curAng+=drift+(rnd()-0.5)*(30*Math.PI/180);
    var len=depth===0?(60+rnd()*50):(60+rnd()*30);
    var nxt=[pts[pts.length-1][0]+Math.cos(curAng)*len, pts[pts.length-1][1]+Math.sin(curAng)*len];
    if(nearSkel(nxt[0],nxt[1],snapLen,70,origin[0],origin[1]))break;
    if(distRiver(nxt[0],nxt[1])<60)break;
    if(sdSet(flatHexes,nxt[0],nxt[1])<-130)break;
    if(Math.min(sdSet(hillHexes,nxt[0],nxt[1]),sdSet(mtnHexes,nxt[0],nxt[1]))>150)break;
    pts.push(nxt);
  }
  if(pts.length<2)return;
  var alen=[0];
  for(var i=1;i<pts.length;i++){var dx=pts[i][0]-pts[i-1][0],dy=pts[i][1]-pts[i-1][1];alen.push(alen[i-1]+Math.sqrt(dx*dx+dy*dy));}
  var total=alen[alen.length-1]||1;
  var amp=[],wid=[];
  for(var j=0;j<pts.length;j++){
    var t=alen[j]/total;
    amp.push(Math.max(0.15,a0*Math.pow(1-t,1.4)));
    wid.push(w0+(35-w0)*t);
  }
  addPolySegs(pts,amp,wid);
  for(var j2=0;j2<pts.length;j2++)skelPts.push(pts[j2]);
  if(depth===0){
    for(var j3=1;j3<pts.length-1;j3++){
      if(alen[j3]/total<0.4)continue;
      if(rnd()<0.35){
        var dirx=pts[j3+1][0]-pts[j3-1][0],diry=pts[j3+1][1]-pts[j3-1][1];
        var pAng=Math.atan2(diry,dirx);
        var side=rnd()<0.5?1:-1;
        growSpur(rnd,pts[j3],pAng+side*(35+rnd()*30)*Math.PI/180,amp[j3]*0.75,wid[j3]*0.7,1);
      }
    }
  }
}
function compute(){
  var rnd=mulberry32(seed);
  segs=[];knolls=[];sinks=[];skelPts=[];
  // crest control points: jittered hill centers + jittered midpoints, mountain bias, flat push
  var ctrl=[];
  for(var i=0;i<hillHexes.length;i++){
    var c=hillHexes[i].c;
    var md=dirTo(c,mtnHexes,700);
    var pt=[c[0]+(rnd()-0.5)*200, c[1]+(rnd()-0.5)*200];
    if(md){pt[0]+=md[0]*140;pt[1]+=md[1]*140;}
    pt=pushFromFlat(pt,0.45);
    ctrl.push(pt);
    if(i<hillHexes.length-1){
      var c2=hillHexes[i+1].c;
      var dx=c2[0]-c[0],dy=c2[1]-c[1];var L=Math.sqrt(dx*dx+dy*dy);
      ctrl.push([(c[0]+c2[0])/2-dy/L*(rnd()-0.5)*300,(c[1]+c2[1])/2+dx/L*(rnd()-0.5)*300]);
    }
  }
  var crest=crSample(ctrl,10); // 41 pts: ctrl j at sample j*10
  // extend both ends ~150 units along end tangents (3 pts of 50 each)
  var head=[],tail=[];
  var hd=[crest[0][0]-crest[1][0],crest[0][1]-crest[1][1]];var hl=Math.sqrt(hd[0]*hd[0]+hd[1]*hd[1])||1;
  var td=[crest[crest.length-1][0]-crest[crest.length-2][0],crest[crest.length-1][1]-crest[crest.length-2][1]];var tl=Math.sqrt(td[0]*td[0]+td[1]*td[1])||1;
  for(var e=3;e>=1;e--)head.push([crest[0][0]+hd[0]/hl*50*e,crest[0][1]+hd[1]/hl*50*e]);
  for(var e2=1;e2<=3;e2++)tail.push([crest[crest.length-1][0]+td[0]/tl*50*e2,crest[crest.length-1][1]+td[1]/tl*50*e2]);
  var cpts=head.concat(crest,tail); // pre-offset = 3
  var n=cpts.length;
  // summit/saddle amplitude + width node profiles (ctrl j -> sample 3 + j*10)
  var s0=0.62+rnd()*0.23, s1=0.62+rnd()*0.23, s2=0.62+rnd()*0.23;
  var d0=0.45+rnd()*0.11, d1=0.45+rnd()*0.11;
  var ampNodes=[[0,0.15],[3,s0],[13,d0],[23,s1],[33,d1],[43,s2],[n-1,0.15]];
  var widNodes=[[0,55],[3,110+rnd()*50],[13,80+rnd()*30],[23,110+rnd()*50],[33,80+rnd()*30],[43,110+rnd()*50],[n-1,55]];
  var camp=interpNodes(ampNodes,n), cwid=interpNodes(widNodes,n);
  addPolySegs(cpts,camp,cwid);
  for(var k0=0;k0<n;k0++)skelPts.push(cpts[k0]);
  // spurs along crest (skip extension zones)
  var sideSign=rnd()<0.5?1:-1;
  var acc=0, nextSpawn=120+rnd()*60;
  for(var ci=4;ci<n-4;ci++){
    var dx2=cpts[ci][0]-cpts[ci-1][0],dy2=cpts[ci][1]-cpts[ci-1][1];
    acc+=Math.sqrt(dx2*dx2+dy2*dy2);
    if(acc<nextSpawn)continue;
    acc=0;nextSpawn=120+rnd()*60;
    var doSpawn=rnd()<0.7;
    var tx=cpts[ci+1][0]-cpts[ci-1][0],ty=cpts[ci+1][1]-cpts[ci-1][1];
    var tAng=Math.atan2(ty,tx);
    if(doSpawn)growSpur(rnd,cpts[ci],tAng+sideSign*(30+rnd()*40)*Math.PI/180,0.85*camp[ci],0.8*cwid[ci],0);
    if(rnd()>=0.15)sideSign=-sideSign;
  }
  // knolls: 1-2 per tile, rejection sampled off-skeleton
  var pcaAng=Math.atan2(hillHexes[2].c[1]-hillHexes[0].c[1],hillHexes[2].c[0]-hillHexes[0].c[0]);
  for(var hi=0;hi<hillHexes.length;hi++){
    var want=1+(rnd()<0.5?1:0), got=0;
    for(var att=0;att<8&&got<want;att++){
      var kx=hillHexes[hi].c[0]+(rnd()-0.5)*460, ky=hillHexes[hi].c[1]+(rnd()-0.5)*400;
      if(sdSet(hillHexes,kx,ky)>-30)continue;
      var kd2=1e18;
      for(var sp=0;sp<skelPts.length;sp++){var ddx=kx-skelPts[sp][0],ddy=ky-skelPts[sp][1];var dd=ddx*ddx+ddy*ddy;if(dd<kd2)kd2=dd;}
      var kd=Math.sqrt(kd2);
      if(kd<90||kd>260)continue;
      var ea=60+rnd()*70, eb=ea*(0.65+rnd()*0.35);
      var th=pcaAng+(rnd()-0.5)*(50*Math.PI/180);
      knolls.push([kx,ky,Math.cos(th),Math.sin(th),1/(ea*ea),1/(eb*eb),0.30+rnd()*0.20]);
      got++;
    }
  }
  // sinks + one ravine
  for(var sn=0;sn<2;sn++){
    var hh=hillHexes[Math.floor(rnd()*hillHexes.length)];
    var R=60+rnd()*80;
    sinks.push([hh.c[0]+(rnd()-0.5)*460,hh.c[1]+(rnd()-0.5)*400,R*R,0.12+rnd()*0.25]);
  }
  var hr=hillHexes[Math.floor(rnd()*hillHexes.length)];
  var st=[hr.c[0]+(rnd()-0.5)*440,hr.c[1]+(rnd()-0.5)*380];
  var ra=rnd()*6.283, rl=380+rnd()*220;
  var rdx=Math.cos(ra),rdy=Math.sin(ra);
  var mid=[st[0]-rdy*(rnd()-0.5)*240,st[1]+rdx*(rnd()-0.5)*240];
  ravine=crSample([[st[0]-rdx*rl,st[1]-rdy*rl],mid,[st[0]+rdx*rl,st[1]+rdy*rl]],10);
  // ---- field on half-res grid
  var nSegs=segs.length;
  for(var gy=0;gy<gh;gy++){
    for(var gx=0;gx<gw;gx++){
      var px=gx*2, py=gy*2;
      var x=(px-OX)/S, y=(py-OY)/S;
      var sdH=sdSet(hillHexes,x,y), sdM=sdSet(mtnHexes,x,y), sdF=sdSet(flatHexes,x,y);
      var gi=gy*gw+gx;
      vGrid[gi]=0;
      if(sdH>40&&sdF>0&&sdM>40&&(sdH>130||sdF>250))continue;
      // domain warp (hill terms only)
      var wx=x+((noiseOct(x,y,seed+501,1/140,1,1)-0.5)*52+(noiseOct(x,y,seed+502,1/55,1,1)-0.5)*20);
      var wy=y+((noiseOct(x,y,seed+601,1/140,1,1)-0.5)*52+(noiseOct(x,y,seed+602,1/55,1,1)-0.5)*20);
      var v=0, minD2=1e18;
      for(var si=0;si<nSegs;si++){
        var sg=segs[si];
        var rx=wx-sg[0], ry=wy-sg[1];
        var t=(rx*sg[2]+ry*sg[3])*sg[4];t=t<0?0:(t>1?1:t);
        var ex=rx-sg[2]*t, ey=ry-sg[3]*t;
        var d2=ex*ex+ey*ey;
        if(d2<minD2)minD2=d2;
        var w=sg[7]+sg[8]*t;
        if(d2<w*w){
          var q2=d2/(w*w);var om=1-q2;
          var g=(sg[5]+sg[6]*t)*om*om;
          if(g>v){var h=0.5+0.5*(g-v)/0.05;h=h>1?1:h;v=v+(g-v)*h+0.05*h*(1-h);}
          else{var h2=0.5+0.5*(v-g)/0.05;h2=h2>1?1:h2;v=g+(v-g)*h2+0.05*h2*(1-h2);}
        }
      }
      for(var ki=0;ki<knolls.length;ki++){
        var kn=knolls[ki];
        var dxk=wx-kn[0],dyk=wy-kn[1];
        var u=kn[2]*dxk+kn[3]*dyk, vv2=-kn[3]*dxk+kn[2]*dyk;
        var q2k=u*u*kn[4]+vv2*vv2*kn[5];
        if(q2k<1){var omk=1-q2k;var gk=kn[6]*omk*omk*omk;v=smax(v,gk,0.05);}
      }
      v+=0.16*sstep(Math.sqrt(minD2),420,60);
      v*=1+0.3*(noiseOct(wx,wy,seed,1/200,3,0.55)-0.5);
      if(v>0.03)v+=0.05*(noiseOct(wx,wy,seed+991,1/55,1,1)-0.5);
      for(var sj=0;sj<sinks.length;sj++){var sk=sinks[sj];var sdx=wx-sk[0],sdy=wy-sk[1];var sd2=sdx*sdx+sdy*sdy;if(sd2<sk[2]){var ts=1-sd2/sk[2];v-=sk[3]*ts*ts;}}
      if(v<0)v=0;
      // ravine erodes hill terms only; the mountain skirt keeps its lv-3 floor
      v*=0.05+0.95*sstep(distPoly(ravine,wx,wy),20,95);
      var vm=0;
      if(sdM<=0){vm=L3*(1+Math.min(1,-sdM/200)*0.6);}
      else{vm=L3*sstep(sdM,380,0);}
      v+=vm;
      if(v<=0)continue;
      var fDef=sstep(sdUnion(domHexes,domKeep,x,y),40,-120);
      fDef=Math.max(fDef,sstep(sdM,40,0));
      var fFlat=sstep(sdUnion(hillHexes,hillKeep,x,y),130,-96);
      var infl=sstep(sdF,250,0);
      v*=fDef*(1-infl)+fFlat*infl;
      v*=sstep(distRiver(x,y),50,170);
      if(sdF<=0&&v>L3*0.92)v=L3*0.92;
      vGrid[gi]=v>0?v:0;
    }
  }
  // ---- full-res band + fine-band assignment (bilerp)
  for(var py2=0;py2<H;py2++){
    var gyf=py2*0.5, iy=Math.floor(gyf), fy=gyf-iy;
    var iy1=iy+1<gh?iy+1:gh-1;
    for(var px2=0;px2<W;px2++){
      var gxf=px2*0.5, ix=Math.floor(gxf), fx=gxf-ix;
      var ix1=ix+1<gw?ix+1:gw-1;
      var v00=vGrid[iy*gw+ix],v10=vGrid[iy*gw+ix1],v01=vGrid[iy1*gw+ix],v11=vGrid[iy1*gw+ix1];
      var vv=(v00+(v10-v00)*fx)+((v01+(v11-v01)*fx)-(v00+(v10-v00)*fx))*fy;
      var idx=py2*W+px2;
      if(vv<=0){band[idx]=0;fb[idx]=0;continue;}
      var kb=0;
      for(var ti=0;ti<THR.length;ti++){if(vv>=THR[ti])kb=ti+1;else break;}
      band[idx]=kb;
      fb[idx]=Math.floor(vv/0.072);
    }
  }
}
function hexPath(c){ctx.beginPath();for(var i=0;i<6;i++){var X=c[0]+HEXV[i][0]-270,Y=c[1]+HEXV[i][1]-240;if(i)ctx.lineTo(X,Y);else ctx.moveTo(X,Y);}ctx.closePath();}
function draw(){
  ctx.fillStyle='#e9dfc6';ctx.fillRect(0,0,W,H);
  ctx.save();ctx.translate(OX,OY);ctx.scale(S,S);
  for(var q=-1;q<=3;q++)for(var r=-1;r<=2;r++){hexPath(hexCenter(q,r));ctx.fillStyle='#ddd6b0';ctx.fill();}
  hexPath(mtnHexes[0].c);ctx.fillStyle='#cfc4a4';ctx.fill();
  hexPath(flatHexes[0].c);ctx.fillStyle='#e4dfb4';ctx.fill();
  ctx.restore();
  var img=ctx.getImageData(0,0,W,H),d=img.data;
  var cols=BANDS.map(function(hx){return [parseInt(hx.slice(1,3),16),parseInt(hx.slice(3,5),16),parseInt(hx.slice(5,7),16)];});
  for(var py=0;py<H;py++)for(var px=0;px<W;px++){
    var idx=py*W+px, k=band[idx];if(!k)continue;
    var i=idx*4, c=cols[k-1];
    var kl=px>0?band[idx-1]:k, ku=py>0?band[idx-W]:k;
    var m=1;
    if(kl!==k||ku!==k)m=0.62;
    else{
      var fl=px>0?fb[idx-1]:fb[idx], fu=py>0?fb[idx-W]:fb[idx];
      if(fl!==fb[idx]||fu!==fb[idx])m=0.84;
    }
    d[i]=c[0]*m;d[i+1]=c[1]*m;d[i+2]=c[2]*m;d[i+3]=255;
  }
  ctx.putImageData(img,0,0);
  ctx.save();ctx.translate(OX,OY);ctx.scale(S,S);
  ctx.lineWidth=3;ctx.strokeStyle='rgba(60,50,20,0.18)';
  for(var q2=-1;q2<=3;q2++)for(var r2=-1;r2<=2;r2++){hexPath(hexCenter(q2,r2));ctx.stroke();}
  ctx.lineWidth=6;ctx.strokeStyle='rgba(80,60,30,0.5)';
  hexPath(mtnHexes[0].c);ctx.stroke();
  ctx.lineWidth=5;ctx.strokeStyle='rgba(120,110,60,0.5)';
  hexPath(flatHexes[0].c);ctx.stroke();
  ctx.fillStyle='rgba(60,50,20,0.5)';ctx.font='500 30px sans-serif';
  for(var hi=0;hi<hillHexes.length;hi++){var hc=hillHexes[hi].c;ctx.fillText('hill tile',hc[0]-55,hc[1]+200);}
  ctx.fillStyle='rgba(60,40,20,0.65)';
  ctx.fillText('mountain (edge = lv 3)',mtnHexes[0].c[0]-160,mtnHexes[0].c[1]+170);
  ctx.fillText('flat tile (lv 1-2 spill only)',flatHexes[0].c[0]-185,flatHexes[0].c[1]-70);
  ctx.beginPath();
  for(var rp=0;rp<rivPts.length;rp++){if(rp)ctx.lineTo(rivPts[rp][0],rivPts[rp][1]);else ctx.moveTo(rivPts[rp][0],rivPts[rp][1]);}
  ctx.strokeStyle='#2d68c4';ctx.lineWidth=15;ctx.lineCap='round';ctx.lineJoin='round';ctx.stroke();
  if(document.getElementById('blk').checked){
    ctx.fillStyle='rgba(190,60,50,0.30)';ctx.strokeStyle='rgba(150,40,35,0.45)';ctx.lineWidth=1.5;
    var sub=20;
    for(var gy=-260;gy<800;gy+=sub)for(var gx=-260;gx<1400;gx+=sub){
      var cx=gx+sub/2, cy=gy+sub/2;
      var ppx=Math.round(cx*S+OX), ppy=Math.round(cy*S+OY);
      if(ppx<0||ppx>=W||ppy<0||ppy>=H)continue;
      if(band[ppy*W+ppx]>=BLOCK_FROM){ctx.fillRect(gx,gy,sub,sub);ctx.strokeRect(gx,gy,sub,sub);}
    }
  }
  ctx.restore();
}
function run(){compute();draw();}
document.getElementById('reroll').onclick=function(){seed=(Math.random()*1e9)|0;run();};
document.getElementById('blk').onchange=draw;
run();
if(typeof module!=='undefined'&&module.exports){
  module.exports={
    run:run, setSeed:function(s){seed=s;}, sdSet:sdSet,
    stats:function(){return {segs:segs.length,knolls:knolls.length,skel:skelPts.length,
      band:band,vGrid:vGrid,W:W,H:H,S:S,OX:OX,OY:OY,gw:gw,gh:gh,THR:THR,
      hillHexes:hillHexes,mtnHexes:mtnHexes,flatHexes:flatHexes};},
  };
}
})();
