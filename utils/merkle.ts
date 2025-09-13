import { StandardMerkleTree } from "@openzeppelin/merkle-tree";

function main() {
    
  const addresses = [
    ["0x0000000000000000000000000000000000000002", "5000000000000000000"],
    ["0x0000000000000000000000000000000000000003", "2500000000000000000"],
    ["0x0000000000000000000000000000000000000004", "3000000000000000000"],
    ["0x0000000000000000000000000000000000000005", "5000000000000000000"],
    ["0x0000000000000000000000000000000000000006", "10000000000000000000"],

  ];

  const tree = StandardMerkleTree.of(addresses, ["address", "uint256"]);
  console.log("Merkle Root:", tree.root);

    for (const [i, v] of tree.entries()) {
        const proof = tree.getProof(i);
        console.log('Address:', v[1], "Proof", proof);
    }

}

main();
