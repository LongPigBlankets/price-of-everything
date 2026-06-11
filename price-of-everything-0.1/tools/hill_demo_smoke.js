// Headless smoke test for hill_demo_draft.js field invariants.
var ctxStub={
  fillRect:function(){},save:function(){},translate:function(){},scale:function(){},
  beginPath:function(){},moveTo:function(){},lineTo:function(){},closePath:function(){},
  fill:function(){},restore:function(){},stroke:function(){},fillText:function(){},
  strokeRect:function(){},putImageData:function(){},
  getImageData:function(){return {data:new Uint8ClampedArray(680*400*4)};},
};
var blk={checked:false};
global.document={getElementById:function(id){
  if(id==='cv')return {width:680,height:400,getContext:function(){return ctxStub;}};
  if(id==='blk')return blk;
  return {};
}};
var mod=require('./hill_demo_draft.js');

function checkSeed(seed){
  mod.setSeed(seed);mod.run();
  var s=mod.stats();
  var res={seed:seed};
  // 1. spurs actually spawned (crest alone contributes ~46 segments)
  res.segs=s.segs; res.spurSegs=s.segs-46; res.knolls=s.knolls;
  // 2. mountain-edge contract: v >= 0.41 a few units inside the shared edge y=240, x 540..810
  var ok=0,tot=0;
  for(var x=555;x<=795;x+=5){
    var y=232;
    var px=Math.round(x*s.S+s.OX), py=Math.round(y*s.S+s.OY);
    var gx=Math.round(px/2), gy=Math.round(py/2);
    if(gx<0||gx>=s.gw||gy<0||gy>=s.gh)continue;
    tot++;
    if(s.vGrid[gy*s.gw+gx]>=0.41)ok++;
  }
  res.mtnEdgeFrac=tot?+(ok/tot).toFixed(3):0;
  // 3. flat tile: spill area share (band>=1) and zero band>=3 pixels inside flat hex
  var inFlat=0,spill=0,blocked=0;
  for(var py2=0;py2<s.H;py2++)for(var px2=0;px2<s.W;px2++){
    var gxg=(px2-s.OX)/s.S, gyg=(py2-s.OY)/s.S;
    if(mod.sdSet(s.flatHexes,gxg,gyg)<0){
      inFlat++;
      var b=s.band[py2*s.W+px2];
      if(b>=1)spill++;
      if(b>=3)blocked++;
    }
  }
  res.flatSpillFrac=inFlat?+(spill/inFlat).toFixed(3):0;
  res.flatBlocked=blocked;
  // 4. band histogram sanity
  var hist=[0,0,0,0,0,0,0];
  for(var i=0;i<s.band.length;i++)hist[s.band[i]]++;
  res.hist=hist;
  res.hasHighBands=(hist[4]+hist[5]+hist[6])>200;
  // 5. determinism: rerun same seed, checksum vGrid
  function csum(g){var c=0;for(var j=0;j<g.length;j+=37)c=(c*31+Math.round(g[j]*1e6))|0;return c;}
  var c1=csum(s.vGrid);
  mod.setSeed(seed);mod.run();
  var c2=csum(mod.stats().vGrid);
  res.deterministic=(c1===c2);
  return res;
}

var seeds=[1337,42,999,31415,777];
var fail=0;
seeds.forEach(function(sd){
  var r=checkSeed(sd);
  var bad=[];
  if(r.spurSegs<3)bad.push('few spurs');
  if(r.mtnEdgeFrac<0.8)bad.push('mtn edge contract '+r.mtnEdgeFrac);
  if(r.flatSpillFrac>0.25)bad.push('flat spill '+r.flatSpillFrac);
  if(r.flatBlocked>0)bad.push('blocked px in flat '+r.flatBlocked);
  if(!r.hasHighBands)bad.push('no high bands');
  if(!r.deterministic)bad.push('non-deterministic');
  if(bad.length)fail++;
  console.log('seed',r.seed,'segs',r.segs,'spurSegs',r.spurSegs,'knolls',r.knolls,
    'mtnEdge',r.mtnEdgeFrac,'flatSpill',r.flatSpillFrac,'flatBlocked',r.flatBlocked,
    'hist',r.hist.join('/'),bad.length?('FAIL: '+bad.join('; ')):'OK');
});
console.log(fail===0?'ALL OK':'FAILURES: '+fail);
