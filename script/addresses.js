#!/usr/bin/env node
const { contracts, doNotUse, network } = require('../deployments.json');

const name = process.argv[2];

if (name) {
  const hit = contracts[name];
  if (!hit) {
    console.error(`unknown contract "${name}" — known: ${Object.keys(contracts).join(', ')}`);
    process.exit(1);
  }
  console.log(hit.address);
} else {
  console.log(`${network.name} (chain ${network.chainId}) — ${network.rpcUrl}\n`);
  const pad = Math.max(...Object.keys(contracts).map((k) => k.length));
  for (const [k, v] of Object.entries(contracts)) {
    console.log(`${k.padEnd(pad)}  ${v.address}`);
  }
  console.log(`\n${doNotUse.length} superseded addresses in doNotUse — do not use these.`);
}
