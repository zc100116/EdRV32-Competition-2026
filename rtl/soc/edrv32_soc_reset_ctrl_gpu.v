// File: edrv32_soc_reset_ctrl_gpu.v
// Spec: gpu-soc-spec 5.1, 5.3, 8.1; sys-subsys-spec 2.10.
// Description: Sequence power-on and sixteen-system-clock software resets.
//              Keep the memory fabric running during either software reset.
// Clock domain: clk_sys, clk_mem, clk_pix, clk_gpu, clk_aud, eth_rx and eth_tx.
module edrv32_soc_reset_ctrl_gpu (
    // Clocks and external asynchronous reset.
    input wire clk_sys_i,
    input wire clk_mem_i,
    input wire clk_pix_i,
    input wire clk_gpu_i,
    input wire clk_aud_i,
    input wire clk_eth_rx_i,
    input wire clk_eth_tx_i,
    input wire rst_n_i,

    // Ready level and clk_sys software request pulses.
    input wire mem_ready_i,
    input wire soft_reset_media_i,
    input wire soft_reset_soc_i,

    // Resets synchronously released in their respective domains.
    output wire rst_sys_por_n_o,
    output wire rst_sys_n_o,
    output wire rst_mem_core_n_o,
    output wire rst_mem_n_o,
    output wire rst_pix_n_o,
    output wire rst_gpu_n_o,
    output wire rst_aud_n_o,
    output wire rst_eth_rx_n_o,
    output wire rst_eth_tx_n_o
);
    wire rst_mem_por_n_w;
    wire mem_ready_w;
    wire media_released_w;
    wire media_copies_n_w;
    wire rst_mem_copy_n_w;
    wire rst_gpu_copy_n_w;
    wire rst_aud_copy_n_w;
    wire rst_pix_copy_n_w;
    wire media_release_n_w;
    wire sys_release_n_w;
    wire soft_active_w;
    reg [4:0] soft_cnt_r;
    reg soft_soc_r;
    reg sys_release_r;

    // Always-on control logic cannot use a reset which it generates itself.
    edrv32_reset_sync u_sys_por (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_sys_por_n_o)
    );
    edrv32_reset_sync u_mem_por (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_mem_por_n_w)
    );
    edrv32_cdc_sync_bit u_mem_ready (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_por_n_w),
        .bit_i(mem_ready_i),
        .bit_o(mem_ready_w)
    );
    edrv32_reset_sync u_mem_core (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_n_i && mem_ready_w),
        .rst_n_o(rst_mem_core_n_o)
    );

    // spec 2.10: the counter survives the resets requested by software.
    always @(posedge clk_sys_i or negedge rst_sys_por_n_o) begin
        if (!rst_sys_por_n_o) begin
            soft_cnt_r <= 5'd0;
            soft_soc_r <= 1'b0;
        end else if (soft_reset_soc_i || soft_reset_media_i) begin
            soft_cnt_r <= 5'd16;
            soft_soc_r <= soft_reset_soc_i;
        end else if (soft_active_w) begin
            soft_cnt_r <= soft_cnt_r - 1'b1;
            if (soft_cnt_r == 5'd1) begin
                soft_soc_r <= 1'b0;
            end
        end
    end
    assign soft_active_w = soft_cnt_r != 5'd0;
    assign media_release_n_w = rst_mem_core_n_o && !soft_active_w;

    edrv32_reset_sync u_mem (
        .clk_i(clk_mem_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_mem_n_o)
    );
    edrv32_reset_sync u_gpu (
        .clk_i(clk_gpu_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_gpu_n_o)
    );
    edrv32_reset_sync u_pix (
        .clk_i(clk_pix_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_pix_n_o)
    );
    // gpu-soc-spec 8.1: audio joins the common media release request.
    edrv32_reset_sync u_aud (
        .clk_i(clk_aud_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_aud_n_o)
    );
    edrv32_reset_sync u_eth_rx (
        .clk_i(clk_eth_rx_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_eth_rx_n_o)
    );
    edrv32_reset_sync u_eth_tx (
        .clk_i(clk_eth_tx_i),
        .rst_n_i(media_release_n_w),
        .rst_n_o(rst_eth_tx_n_o)
    );

    // spec 2.10 release order: all one-stage engine copies release first.
    edrv32_reset_copy u_mem_copy (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_o),
        .rst_n_o(rst_mem_copy_n_w)
    );
    // visual SoC 5.3.5: wait for the copies of the on-board PLL engine domains.
    // ETH clocks come from the PHY, held in reset until software clears
    // PHY_CTRL.PHY_RST, so ETH copies must not gate SYS (gpu-soc-spec 5.3).
    edrv32_reset_copy u_gpu_copy (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_o),
        .rst_n_o(rst_gpu_copy_n_w)
    );
    edrv32_reset_copy u_aud_copy (
        .clk_i(clk_aud_i),
        .rst_n_i(rst_aud_n_o),
        .rst_n_o(rst_aud_copy_n_w)
    );
    edrv32_reset_copy u_pix_copy (
        .clk_i(clk_pix_i),
        .rst_n_i(rst_pix_n_o),
        .rst_n_o(rst_pix_copy_n_w)
    );
    assign media_copies_n_w = rst_mem_copy_n_w && rst_gpu_copy_n_w
        && rst_aud_copy_n_w && rst_pix_copy_n_w;
    edrv32_cdc_sync_bit u_media_released (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_por_n_o && !soft_soc_r),
        .bit_i(media_copies_n_w),
        .bit_o(media_released_w)
    );
    // A media-only reset must not revoke a previously released system reset.
    always @(posedge clk_sys_i or negedge rst_sys_por_n_o) begin
        if (!rst_sys_por_n_o) begin
            sys_release_r <= 1'b0;
        end else if (soft_reset_soc_i || soft_soc_r) begin
            sys_release_r <= 1'b0;
        end else if (media_released_w) begin
            sys_release_r <= 1'b1;
        end
    end
    assign sys_release_n_w = rst_n_i && sys_release_r && !soft_soc_r;
    edrv32_reset_sync u_sys (
        .clk_i(clk_sys_i),
        .rst_n_i(sys_release_n_w),
        .rst_n_o(rst_sys_n_o)
    );
endmodule
