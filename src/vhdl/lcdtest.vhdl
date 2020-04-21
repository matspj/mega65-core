----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    22:30:37 12/10/2013
-- Design Name:
-- Module Name:    container - Behavioral
-- Project Name:
-- Target Devices:
-- Tool versions:
-- Description:
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.cputypes.all;


-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity container is
  Port ( CLK_IN : STD_LOGIC;
--         btnCpuReset : in  STD_LOGIC;
--         irq : in  STD_LOGIC;
--         nmi : in  STD_LOGIC;

         wifirx : out std_logic := '1';
         wifitx : out std_logic := '1';

         i2c1sda : inout std_logic;
         i2c1scl : inout std_logic;

         modem1_pcm_clk_in : in std_logic;
         modem1_pcm_sync_in : in std_logic;
         modem1_pcm_data_in : in std_logic;
         modem1_pcm_data_out : out std_logic;
--         modem1_uart2_rx : inout std_logic;
--         modem1_uart2_tx : out std_logic;
         modem1_uart_rx : inout std_logic;
         modem1_uart_tx : out std_logic;

         modem2_pcm_clk_in : in std_logic;
         modem2_pcm_sync_in : in std_logic;
         modem2_pcm_data_in : in std_logic;
         modem2_pcm_data_out : out std_logic;
--         modem2_uart2_rx : inout std_logic;
--         modem2_uart2_tx : out std_logic;
         modem2_uart_rx : inout std_logic;
         modem2_uart_tx : out std_logic;

         ----------------------------------------------------------------------
         -- MEMS microphones
         ----------------------------------------------------------------------
         micData0 : in std_logic;
         micData1 : in std_logic;
         micClk : out std_logic;

         ----------------------------------------------------------------------
         -- Touch screen interface
         ----------------------------------------------------------------------
         touch_sda : inout std_logic := '1';
         touch_scl : inout std_logic := '1';

         ----------------------------------------------------------------------
         -- CIA1 ports for keyboard/joystick
         ----------------------------------------------------------------------
--         porta_pins : inout  std_logic_vector(7 downto 0);
--         portb_pins : inout  std_logic_vector(7 downto 0);

         ----------------------------------------------------------------------
         -- VGA output
         ----------------------------------------------------------------------
         vga_vsync : out STD_LOGIC;
         vga_hsync : out  STD_LOGIC;
         vga_red : out  UNSIGNED (3 downto 0);
         vga_green : out  UNSIGNED (3 downto 0);
         vga_blue : out  UNSIGNED (3 downto 0);

         ----------------------------------------------------------------------
         -- LCD output
         ----------------------------------------------------------------------
         lcd_vsync : out STD_LOGIC;
         lcd_hsync : out  STD_LOGIC;
         lcd_display_enable : out std_logic;
         lcd_pwm : out std_logic;
         lcd_dclk : out std_logic;
         lcd_red : out  UNSIGNED (5 downto 0);
         lcd_green : out  UNSIGNED (5 downto 0);
         lcd_blue : out  UNSIGNED (5 downto 0);

         ----------------------------------------------------------------------
         -- HyperRAM as expansion RAM
         ----------------------------------------------------------------------
         hr_d : inout unsigned(7 downto 0);
         hr_rwds : inout std_logic;
         hr_reset : out std_logic;
         hr_rsto : out std_logic := '1';
         hr_clk_n : out std_logic;
         hr_clk_p : out std_logic;
         hr_cs0 : out std_logic;
--         hr_cs1 : out std_logic := '1';

         -------------------------------------------------------------------------
         -- Lines for the SDcard interface itself
         -------------------------------------------------------------------------
         sdReset : out std_logic := '0';  -- must be 0 to power SD controller (cs_bo)
         sdClock : out std_logic := 'Z';       -- (sclk_o)
         sdMOSI : out std_logic := 'Z';
         sdMISO : in  std_logic;

         ----------------------------------------------------------------------
         -- Allow the FPGA to turn itself off
         ----------------------------------------------------------------------
         power_down : out std_logic := '1';

         ----------------------------------------------------------------------
         -- Flash RAM for holding config
         ----------------------------------------------------------------------
--         QspiSCK : out std_logic;
         QspiDB : inout unsigned(3 downto 0) := (others => 'Z');
         QspiCSn : out std_logic;

         ----------------------------------------------------------------------
         -- Analog headphone jack output
         -- (amplifier enable is on an IO expander)
         ----------------------------------------------------------------------
         headphone_left : out std_logic;
         headphone_right : out std_logic;

         ----------------------------------------------------------------------
         -- I2S speaker audio output
         ----------------------------------------------------------------------
         i2s_mclk : out std_logic;
         i2s_sync : out std_logic;
         i2s_speaker : out std_logic;
         i2s_bclk : out std_logic := '1'; -- Force 16 cycles per sample,
                                          -- instead of 32

         ----------------------------------------------------------------------
         -- Debug interfaces on TE0725
         ----------------------------------------------------------------------
         led : out std_logic;

         ----------------------------------------------------------------------
         -- UART monitor interface
         ----------------------------------------------------------------------
         monitor_tx : out std_logic;
         monitor_rx : in std_logic

         );
end container;

architecture Behavioral of container is

  component fpgatemp is
    Generic ( DELAY_CYCLES : natural := 480 ); -- 10us @ 48 Mhz
    Port ( clk : in  STD_LOGIC;
           rst : in  STD_LOGIC;
           temp : out  STD_LOGIC_VECTOR (11 downto 0));
  end component;

  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  signal restore_key : std_logic := '1';
  signal osk_toggle_key : std_logic := '1';
  signal joyswap_key : std_logic := '1';
  signal reset_out : std_logic := '1';
  signal cpu_game : std_logic := '1';
  signal cpu_exrom : std_logic := '1';

  signal buffer_vgared : unsigned(7 downto 0);
  signal buffer_vgagreen : unsigned(7 downto 0);
  signal buffer_vgablue : unsigned(7 downto 0);

  signal pixelclock : std_logic;
  signal cpuclock : std_logic;
  signal ethclock : std_logic;
  signal clock41 : std_logic;
  signal clock27 : std_logic;
  signal clock81 : std_logic;
  signal clock120 : std_logic;
  signal clock100 : std_logic;
  signal clock162 : std_logic;
  signal clock325 : std_logic;

  signal segled_counter : unsigned(31 downto 0) := (others => '0');

  signal slow_access_request_toggle : std_logic;
  signal slow_access_ready_toggle : std_logic;
  signal slow_access_write : std_logic;
  signal slow_access_address : unsigned(27 downto 0);
  signal slow_access_wdata : unsigned(7 downto 0);
  signal slow_access_rdata : unsigned(7 downto 0);

  signal sector_buffer_mapped : std_logic;


  signal vgaredignore : unsigned(3 downto 0);
  signal vgagreenignore : unsigned(3 downto 0);
  signal vgablueignore : unsigned(3 downto 0);

  signal porta_pins : std_logic_vector(7 downto 0) := (others => '1');
  signal portb_pins : std_logic_vector(7 downto 0) := (others => '1');

  signal cart_ctrl_dir : std_logic := 'Z';
  signal cart_haddr_dir : std_logic := 'Z';
  signal cart_laddr_dir : std_logic := 'Z';
  signal cart_data_dir : std_logic := 'Z';
  signal cart_phi2 : std_logic := 'Z';
  signal cart_dotclock : std_logic := 'Z';
  signal cart_reset : std_logic := 'Z';

  signal cart_nmi : std_logic := 'Z';
  signal cart_irq : std_logic := 'Z';
  signal cart_dma : std_logic := 'Z';

  signal cart_exrom : std_logic := 'Z';
  signal cart_ba : std_logic := 'Z';
  signal cart_rw : std_logic := 'Z';
  signal cart_roml : std_logic := 'Z';
  signal cart_romh : std_logic := 'Z';
  signal cart_io1 : std_logic := 'Z';
  signal cart_game : std_logic := 'Z';
  signal cart_io2 : std_logic := 'Z';

  signal cart_d : unsigned(7 downto 0) := (others => 'Z');
  signal cart_d_read : unsigned(7 downto 0) := (others => 'Z');
  signal cart_a : unsigned(15 downto 0) := (others => 'Z');

  ----------------------------------------------------------------------
  -- CBM floppy serial port
  ----------------------------------------------------------------------
  signal iec_clk_en : std_logic := 'Z';
  signal iec_data_en : std_logic := 'Z';
  signal iec_data_o : std_logic := 'Z';
  signal iec_reset : std_logic := 'Z';
  signal iec_clk_o : std_logic := 'Z';
  signal iec_data_i : std_logic := '1';
  signal iec_clk_i : std_logic := '1';
  signal iec_atn : std_logic := 'Z';


  -- XXX We should read the real temperature and feed this to the DDR controller
  -- so that it can update timing whenever the temperature changes too much.
  signal fpga_temperature : std_logic_vector(11 downto 0) := (others => '0');

  signal dummy : std_logic_vector(2 downto 0);
  signal sawtooth_phase : integer := 0;
  signal sawtooth_counter : integer := 0;
  signal sawtooth_level : integer := 0;

  signal pal50_select : std_logic;

  -- Dummy signals for stub / not yet implemented interfaces
  signal eth_mdio : std_logic := '0';
  signal c65uart_rx : std_logic := '1';

  signal pin_number : integer;

  signal expansionram_read : std_logic;
  signal expansionram_write : std_logic;
  signal expansionram_rdata : unsigned(7 downto 0);
  signal expansionram_wdata : unsigned(7 downto 0);
  signal expansionram_address : unsigned(26 downto 0);
  signal expansionram_data_ready_strobe : std_logic;
  signal expansionram_busy : std_logic;

  signal dummypins : std_logic_vector(1 to 100) := (others => '0');

  signal i2c_joya_fire : std_logic;
  signal i2c_joya_left : std_logic;
  signal i2c_joya_right : std_logic;
  signal i2c_joya_up : std_logic;
  signal i2c_joya_down : std_logic;
  signal i2c_joyb_fire : std_logic;
  signal i2c_joyb_left : std_logic;
  signal i2c_joyb_right : std_logic;
  signal i2c_joyb_up : std_logic;
  signal i2c_joyb_down : std_logic;

  signal i2c_button2 : std_logic;
  signal i2c_button3 : std_logic;
  signal i2c_button4 : std_logic;
  signal i2c_black2 : std_logic;
  signal i2c_black3 : std_logic;
  signal i2c_black4 : std_logic;

  signal widget_matrix_col : std_logic_vector(7 downto 0) := (others => '1');

  signal qspi_clock : std_logic;

  signal current_cache_line : cache_row_t := (others => (others => '0'));
  signal current_cache_line_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_valid : std_logic := '0';
  
begin

--STARTUPE2:STARTUPBlock--7Series

--XilinxHDLLibrariesGuide,version2012.4
  STARTUPE2_inst: STARTUPE2
    generic map(PROG_USR=>"FALSE", --Activate program event security feature.
                                   --Requires encrypted bitstreams.
  SIM_CCLK_FREQ=>10.0 --Set the Configuration Clock Frequency(ns) for simulation.
    )
    port map(
--      CFGCLK=>CFGCLK,--1-bit output: Configuration main clock output
--      CFGMCLK=>CFGMCLK,--1-bit output: Configuration internal oscillator
                              --clock output
--             EOS=>EOS,--1-bit output: Active high output signal indicating the
                      --End Of Startup.
--             PREQ=>PREQ,--1-bit output: PROGRAM request to fabric output
             CLK=>'0',--1-bit input: User start-up clock input
             GSR=>'0',--1-bit input: Global Set/Reset input (GSR cannot be used
                      --for the port name)
             GTS=>'0',--1-bit input: Global 3-state input (GTS cannot be used
                      --for the port name)
             KEYCLEARB=>'0',--1-bit input: Clear AES Decrypter Key input
                                  --from Battery-Backed RAM (BBRAM)
             PACK=>'0',--1-bit input: PROGRAM acknowledge input

             -- Put CPU clock out on the QSPI CLOCK pin
             USRCCLKO=>qspi_clock,--1-bit input: User CCLK input
             USRCCLKTS=>'0',--1-bit input: User CCLK 3-state enable input

             -- Assert DONE pin
             USRDONEO=>'1',--1-bit input: User DONE pin output control
             USRDONETS=>'1' --1-bit input: User DONE 3-state enable output
             );
-- End of STARTUPE2_inst instantiation

  
  dotclock1: entity work.dotclock100
    port map ( clk_in1 => CLK_IN,
               clock100 => clock100,
               clock81 => pixelclock, -- 80MHz
               clock41 => cpuclock, -- 40MHz
               clock50 => ethclock,
               clock162 => clock162,
               clock27 => clock27,
               clock325 => clock325
               );


  pixel0: entity work.pixel_driver
    port map (
               clock81 => pixelclock, -- 80MHz
               clock162 => clock162,
               clock27 => clock27,
               cpuclock => cpuclock,
--               phi_out => phi,

--      pixel_strobe_out => external_pixel_strobe,
      
      -- Configuration information from the VIC-IV
      hsync_invert => '0',
      vsync_invert => '0',
               pal50_select => '0',
               vga60_select => '0',
      test_pattern_enable => '1',
      
      -- Framing information for VIC-IV
--      x_zero => external_frame_x_zero,     
--      y_zero => external_frame_y_zero,     

      -- Pixel data from the video pipeline
      -- (clocked at 100MHz pixel clock)
      red_i => (others => '1'),
      green_i => (others => '1'),
      blue_i => (others => '1'),

      -- The pixel for direct output to VGA pins
      -- It is clocked at the correct pixel
--      red_no => vgared,
--      green_no => vgagreen,
--      blue_no => vgablue,      

      red_o => lcd_red,
      green_o => lcd_green,
      blue_o => lec_blue,
               
 --     hsync => hdmi_hsync,
 --     vsync => vsync,  -- for HDMI
 --     vga_hsync => vga_hsync,      -- for VGA          

      -- And the variations on those signals for the LCD display
      lcd_hsync => lcd_hsync,               
      lcd_vsync => lcd_vsync,
      fullwidth_dataenable => lcd_display_enable
--      lcd_inletterbox => lcd_inletterbox,
--      vga_inletterbox => vga_inletterbox

      );


  -- XXX Ethernet should be 250Mbit fibre port on this board
  -- eth_clock <= cpuclock;

end Behavioral;
