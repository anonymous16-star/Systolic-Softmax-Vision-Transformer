`timescale 1ns / 1ps
// =============================================================================
// boothencoder - Radix-4 Booth encoder for 8-bit signed multiplier K
//
// The 8-bit K is zero-extended to 9 bits: kext = {K, 1'b0}
// Then divided into four overlapping 3-bit groups for Radix-4 Booth:
//
//   kext[8:0]  = {K[7], K[6], K[5], K[4], K[3], K[2], K[1], K[0], 0}
//                 ^--- sign extension of MSB
//
//   bu4 = kext[2:0]  -> group for bits K[1:0] (LSB group, processed first)
//   bu3 = kext[4:2]  -> group for bits K[3:2]
//   bu2 = kext[6:4]  -> group for bits K[5:4]
//   bu1 = kext[8:6]  -> group for bits K[7:6] (MSB group)
//
// Note: kext must be sign-extended to 9 bits: kext = {{1{K[7]}}, K, 1'b0}
// The caller (BSPE) must provide a properly sign-extended 9-bit kext.
// =============================================================================

module boothencoder (
    input  [8:0] kext,          // sign-extended K with appended 0: {K[7],K,1'b0}
    output [2:0] bu1,           // MSB group  (bits 8:6)
    output [2:0] bu2,           // group      (bits 6:4)
    output [2:0] bu3,           // group      (bits 4:2)
    output [2:0] bu4            // LSB group  (bits 2:0)
);

    assign bu1 = kext[8:6];
    assign bu2 = kext[6:4];
    assign bu3 = kext[4:2];
    assign bu4 = kext[2:0];

endmodule