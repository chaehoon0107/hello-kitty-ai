const fs = require('fs');
const MeshoptDecoder = require('./meshopt_decoder.cjs');
(async () => {
  await MeshoptDecoder.ready;
  const src = fs.readFileSync(process.argv[2]);
  const jl = src.readUInt32LE(12);
  const doc = JSON.parse(src.subarray(20, 20 + jl).toString());
  const bin = src.subarray(28 + jl);
  const parts = []; let offset = 0;
  for (const view of doc.bufferViews) {
    const ext = view.extensions?.EXT_meshopt_compression;
    let data;
    if (ext) {
      data = Buffer.alloc(ext.count * ext.byteStride);
      MeshoptDecoder.decodeGltfBuffer(data, ext.count, ext.byteStride,
        bin.subarray(ext.byteOffset || 0, (ext.byteOffset || 0) + ext.byteLength), ext.mode, ext.filter);
      delete view.extensions;
    } else data = Buffer.from(bin.subarray(view.byteOffset || 0, (view.byteOffset || 0) + view.byteLength));
    const pad = (4 - offset % 4) % 4;
    if (pad) {parts.push(Buffer.alloc(pad));offset += pad;}
    view.buffer = 0; view.byteOffset = offset; view.byteLength = data.length;
    parts.push(data); offset += data.length;
  }
  doc.buffers = [{byteLength: offset}];
  for (const key of ['extensionsUsed','extensionsRequired']) {
    doc[key] = doc[key].filter(x => x !== 'EXT_meshopt_compression');
    if (!doc[key].length) delete doc[key];
  }
  let json = Buffer.from(JSON.stringify(doc));
  json = Buffer.concat([json,Buffer.alloc((4-json.length%4)%4,32)]);
  let output = Buffer.concat(parts);
  output = Buffer.concat([output,Buffer.alloc((4-output.length%4)%4)]);
  const head = Buffer.alloc(20); head.writeUInt32LE(0x46546c67);head.writeUInt32LE(2,4);
  head.writeUInt32LE(28+json.length+output.length,8);head.writeUInt32LE(json.length,12);head.writeUInt32LE(0x4e4f534a,16);
  const bh=Buffer.alloc(8);bh.writeUInt32LE(output.length);bh.writeUInt32LE(0x004e4942,4);
  fs.writeFileSync(process.argv[3],Buffer.concat([head,json,bh,output]));
  console.log('Decoded mesh:', doc.accessors[0].count, 'vertices');
})();
