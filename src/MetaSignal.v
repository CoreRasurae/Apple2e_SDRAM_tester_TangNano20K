// SPDX-License-Identifier: BSD-3-Clause
/*
 * Metastability compensation for cross-domain signal
 *
 * Copyright (C) 2023 Luís Mendes <luis.p.mendes@gmail.com>
 */
module MetaSignal (input clk, input signalIn, output signalOut);

reg a = 1'b0, b = 1'b0;

always @(posedge clk)
begin
    a <= signalIn;
    b <= a;
end

assign signalOut = b;

endmodule
