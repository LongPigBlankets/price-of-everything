const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
class Sheet {
 constructor(rows = []) { this.rows = rows; }
 getMaxColumns(){return this.maxColumns || 26;}
 insertColumnsAfter(at, count){this.maxColumns = at + count;}
 getLastRow(){return this.rows.length;}
 getLastColumn(){return this.rows[0]?.length || 0;}
 setFrozenRows(){}
 appendRow(row){this.rows.push(row);}
 getRange(r,c,n,m){return {getValues:()=>Array.from({length:n},(_,i)=>Array.from({length:m},(_,j)=>this.rows[r-1+i]?.[c-1+j] ?? '')),setValues:rows=>rows.forEach((row,i)=>row.forEach((v,j)=>{this.rows[r-1+i] ||= [];this.rows[r-1+i][c-1+j]=v;}))};}
}
const sheets={};
const ctx={SpreadsheetApp:{getActive:()=>({getSheetByName:n=>sheets[n],insertSheet:n=>sheets[n]=new Sheet()})},LockService:{getScriptLock:()=>({waitLock(){},releaseLock(){}})},ContentService:{createTextOutput:s=>s}};
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(require('path').join(__dirname, 'Code.gs'),'utf8'),ctx);
const header=vm.runInContext('FIXED.slice(0, -INTERACTIONS.length)',ctx);
sheets.turns=new Sheet([Array.from(header)]);
const token=vm.runInContext('TOKEN',ctx);
const payload={token,client:{version:'test',os:'Windows'},run:{},end:{reason:'quit_to_desktop',turn:2},run_id:'r',session_id:'s',player_id:'p',turns:[{turn:1,interactions:{search_used:2}}],events:[{event_id:'s:1',session_id:'s',turn:2,action:'search_used',interface:'encyclopedia'}]};
assert.equal(ctx.doPost({postData:{contents:JSON.stringify(payload)}}),'ok');
assert.equal(sheets.turns.rows.length,2);
assert.equal(sheets.turns.rows[1][sheets.turns.rows[0].indexOf('search_used')],2);
assert.equal(sheets.events.rows[1][5],2); // unresolved-turn action survives export
ctx.doPost({postData:{contents:JSON.stringify(payload)}});
assert.equal(sheets.events.rows.length,2);
assert.equal(sheets.turns.rows.length,2);
assert.equal(sheets.turns.rows[0][0],'received_at');
console.log('Receiver tests passed: additive headers, counts, pending-turn events, retry deduplication.');
