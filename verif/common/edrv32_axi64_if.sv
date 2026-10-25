// edrv32_axi64_if.sv
// cache-spec 3; independent module verification.
// Clock domain: clk_sys.
interface edrv32_axi64_if;
    logic [3:0] awid;
    logic [31:0] awaddr;
    logic [7:0] awlen;
    logic [2:0] awsize;
    logic [1:0] awburst;
    logic awvalid;
    logic awready;
    logic [3:0] arid;
    logic [31:0] araddr;
    logic [7:0] arlen;
    logic [2:0] arsize;
    logic [1:0] arburst;
    logic arvalid;
    logic arready;
    logic [63:0] wdata;
    logic [7:0] wstrb;
    logic wlast;
    logic wvalid;
    logic wready;
    logic [3:0] bid;
    logic [1:0] bresp;
    logic bvalid;
    logic bready;
    logic [3:0] rid;
    logic [63:0] rdata;
    logic [1:0] rresp;
    logic rlast;
    logic rvalid;
    logic rready;
endinterface
