// Run: node test_menu_model.js. No packages or real lights required.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync(`${__dirname}/plugin/GoveeMenuModel.js`, 'utf8'), model);
const plain = value => JSON.parse(JSON.stringify(value));
const data = {
  devices: [{mac:'AA:01', name:'Desk', label:'Same name', online:true, power:1, brightness:40},
            {mac:'AA:02', name:'Desk 2', label:'Same name', online:false, power:null}],
  rooms: {'Home office':['AA:01']}, scenes:['evening']
};
const targets = plain(model.targets(data));
const device = targets.find(r => r.id === 'AA:02');
assert.equal(targets.filter(r => r.label === 'Same name').length, 2);
assert.equal(model.filter(targets, 'aa:02')[0].id, 'AA:02');
assert.equal(model.filter(targets, 'HOME OFFICE')[0].target, 'room:Home office');
assert.equal(model.filter(targets, 'offline')[0].id, 'AA:02');
assert.deepEqual(plain(model.formCommand('brightness', '040', device)), ['--json','brightness','40','AA:02']);
for (const value of ['-1','101','1.5','', 'NaN']) assert.throws(() => model.formCommand('brightness',value,device));
assert.deepEqual(plain(model.formCommand('color','#FF8800',device)), ['--json','color','#FF8800','AA:02']);
assert.throws(() => model.formCommand('color','red; command',device));
assert.deepEqual(plain(model.formCommand('label','',device)), ['label','AA:02','']);
assert.deepEqual(plain(model.formCommand('newroom','Home office',device)), ['rooms','assign','Home office','AA:02']);
for (const name of ['','ALL','other','none']) assert.throws(() => model.formCommand('newroom',name,device));
assert.deepEqual(plain(model.rows('scenes',data,null)[0].args), ['--json','scene','evening']);
assert.deepEqual(plain(model.rows('rooms',data,device).find(r => r.id === 'Home office').args), ['rooms','assign','Home office','AA:02']);
assert.equal(model.actions(targets.find(r => r.kind === 'other')).some(r => r.form === 'rename'), false);
assert.equal(model.targets({devices:[],rooms:{},scenes:[]}).some(r => r.target === 'all'), false);
assert.match(model.resultMessage(true, JSON.stringify({results:[{status:'unverified'}]})), /not yet verified/);
assert.match(model.resultMessage(false, JSON.stringify({results:[{status:'failed',device:'AA:02',error:'offline'}]})), /AA:02: offline/);
console.log('Menu model: targets, filtering, all actions, validation and result messages passed');
