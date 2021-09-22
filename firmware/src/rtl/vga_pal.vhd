--------------------------------------------------------------------------------
--  ПРОШИВКА ПЛИС ДЛЯ УСТРОЙСТВА: "ZXKit1 - ПЛАТА VGA & PAL"                  --                        
--  ВЕРСИЯ:  V2.0.8.08                                          ДАТА: 091223  --
--  АВТОР:   САБИРЖАНОВ ВАДИМ                                                 --
--
--  Modified by Andy Karpov
--  2020-07-20: Added profi video mode support and forced switch via DS80
--  2020-07-20: Replaced ext video ram with 2-port fpga sram
--  2020-08-07: cleanup, refactoring
--------------------------------------------------------------------------------

library IEEE;
library altera; 
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use altera.altera_primitives_components.all;

entity VGA_PAL is
	generic 
	(
		inverse_ksi 		 : boolean := false;
		inverse_ssi 		 : boolean := false;
		inverse_f 			 : boolean := false
	);
	port
	(

--------------------------------------------------------------------------------
--                 ВХОДНЫЕ СИГНАЛЫ ПЛИС СО СПЕКТРУМА                  091103  --
--------------------------------------------------------------------------------

RGB_IN 		: in std_logic_vector(23 downto 0); -- 8R8G8B
DS80			: in std_logic := '0';
KSI_IN      : in std_logic := '1'; -- кадровые синхроимпульсы
SSI_IN      : in std_logic := '1'; -- строчные синхроимпульсы
CLK         : in std_logic := '1'; -- тактовые импульсы частотой 14 / 12 МГц
CLK2       	: in std_logic := '1'; -- удвоенная CLK
EN 			: in std_logic := '1'; -- включен ли даблер или отдавать сырые сигналы
                                      
--------------------------------------------------------------------------------
--                     ВЫХОДНЫЕ ПОРТЫ ПЛИС ДЛЯ VGA                    090728  --
--------------------------------------------------------------------------------

RGB_O 	  : out std_logic_vector(23 downto 0) := (others => '0'); -- VGA RGB
VGA_BLANK_O: out std_logic := '1'; -- гасящие импульсы для VGA
VSYNC_VGA  : out std_logic := '1'; -- кадровые синхроимпульсы
HSYNC_VGA  : out std_logic := '1' -- строчные синхроимпульсы

);
    end VGA_PAL;
architecture RTL of VGA_PAL is

--------------------------------------------------------------------------------
--                       ВНУТРЕННИЕ СИГНАЛЫ ПЛИС                      090804  --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                   НОРМАЛИЗОВАННЫЕ ВХОДНЫЕ СИГНАЛЫ                  090805  --
--------------------------------------------------------------------------------

signal RGB 	  : std_logic_vector(23 downto 0);
signal RGBI_CLK : std_logic; -- тактовый сигнал входного кода цвета

signal KSI    : std_logic; -- кадровые синхроимпульсы
signal SSI    : std_logic; -- строчные синхроимпульсы

--------------------------------------------------------------------------------
--                     СИГНАЛЫ ДЛЯ СБРОСА СЧЕТЧИКОВ                   091220  --
--------------------------------------------------------------------------------

signal KSI_1  : std_logic; -- выборка кадрового синхроимпульса
signal KSI_2  : std_logic; -- задержанные кадровые синхроимпульсы
signal SSI_2  : std_logic; -- задержанные строчные синхроимпульсы

--------------------------------------------------------------------------------
--              СЧЕТЧИКИ И ПАРАМЕТРЫ РАЗВЕРТКИ ДЛЯ VGA И VIDEO        091223  --
--------------------------------------------------------------------------------
-- строчная развертка VGA:

signal VGA_H_CLK     : std_logic; -- сигнал увеличения счетчика тактов в строке
signal VGA_H         : std_logic_vector(8 downto 0); -- счетчик тактов в строке
signal VGA_H_MIN     : std_logic_vector(8 downto 0); -- мин. знач.счетч. тактов
signal VGA_H_MAX     : std_logic_vector(8 downto 0); -- макс.знач.счетч. тактов
signal VGA_SSI1_BGN   : std_logic_vector(9 downto 0); -- начало строчного СИ
signal VGA_SSI1_END   : std_logic_vector(9 downto 0); -- конец  строчного СИ
signal VGA_SSI2_BGN   : std_logic_vector(9 downto 0); -- начало строчного СИ
signal VGA_SSI2_END   : std_logic_vector(9 downto 0); -- конец  строчного СИ
signal VGA_SGI1_BGN   : std_logic_vector(9 downto 0); -- начало строчного ГИ
signal VGA_SGI1_END   : std_logic_vector(9 downto 0); -- конец  строчного ГИ
signal VGA_SGI2_BGN   : std_logic_vector(9 downto 0); -- начало строчного ГИ
signal VGA_SGI2_END   : std_logic_vector(9 downto 0); -- конец  строчного ГИ
--------------------------------------------------------------------------------
-- кадровая развертка VGA:

signal VGA_V_CLK     : std_logic; -- сигнал увеличения счетчика строк в кадре
signal VGA_V         : std_logic_vector(9 downto 0); -- счетчик строк в кадре
signal VGA_V_MIN     : std_logic_vector(9 downto 0); -- мин. знач.счетчика строк
signal VGA_V_MAX     : std_logic_vector(9 downto 0); -- макс.знач.счетчика строк
signal VGA_KSI_BGN   : std_logic_vector(9 downto 0); -- начало кадрового СИ
signal VGA_KSI_END   : std_logic_vector(9 downto 0); -- конец  кадрового СИ
signal VGA_KGI1_END  : std_logic_vector(9 downto 0); -- конец  кадрового ГИ
signal VGA_KGI2_BGN  : std_logic_vector(9 downto 0); -- начало кадрового ГИ
--------------------------------------------------------------------------------
-- строчная развертка VIDEO:

signal VIDEO_H_CLK   : std_logic; -- сигнал увеличения счетчика тактов в строке
signal VIDEO_H       : std_logic_vector(9 downto 0); -- счетчик тактов в строке
signal VIDEO_H_MAX   : std_logic_vector(9 downto 0); -- макс.знач. счетч. тактов
signal VIDEO_SSI_BGN : std_logic_vector(9 downto 0); -- начало строчного СИ
signal VIDEO_SSI_END : std_logic_vector(9 downto 0); -- конец  строчного СИ
signal VIDEO_SGI_BGN : std_logic_vector(9 downto 0); -- начало строчного ГИ
signal VIDEO_SGI_END : std_logic_vector(9 downto 0); -- конец  строчного ГИ
--------------------------------------------------------------------------------
-- кадровая развертка VIDEO:

signal VIDEO_V_CLK   : std_logic;  --сигнал увеличения счетчика строк в кадре
signal VIDEO_V       : std_logic_vector(8 downto 0); -- счетчик строк в кадре
signal VIDEO_V_MAX   : std_logic_vector(8 downto 0); -- макс.знач. счетч. тактов
signal VIDEO_KSI_BGN : std_logic_vector(8 downto 0); -- начало кадрового СИ
signal VIDEO_KSI_END : std_logic_vector(8 downto 0); -- конец  кадрового СИ
signal VIDEO_KGI_BGN : std_logic_vector(8 downto 0); -- начало кадрового ГИ
signal VIDEO_KGI_END : std_logic_vector(8 downto 0); -- конец  кадрового ГИ
signal SCREEN_V_END  : std_logic_vector(8 downto 0); -- конец акт. части экрана
--------------------------------------------------------------------------------
-- тип компьютера/параметры развертки в строке: 

--------------------------------------------------------------------------------
--                     СИНХРОИМПУЛЬСЫ ДЛЯ VGA И VIDEO                 091220  --
--------------------------------------------------------------------------------

signal VGA_KSI      : std_logic; -- кадровые синхроимпульсы для VGA
signal VGA_SSI      : std_logic; -- строчные синхроимпульсы для VGA

signal VIDEO_KSI    : std_logic; -- кадровые синхроимпульсы для VIDEO
signal VIDEO_SSI1   : std_logic; -- основные строчные синхроимпульсы для VIDEO
signal VIDEO_SSI2   : std_logic; -- строчные синхроимпульсы - врезки для VIDEO
signal VIDEO_SYNC   : std_logic; -- синхросмесь для VIDEO

signal VGA_RBGI_CLK : std_logic; -- синхроимпульсы для вывода на VGA 

signal RESET_ZONE   : std_logic; -- сигнал для синхроницации счетчика тактов
signal RESET_H      : std_logic; -- если 0, то можно сбрасывать счетчик тактов    
signal RESET_V      : std_logic; -- если 0, то можно сбрасывать счетчик строк    
 
--------------------------------------------------------------------------------
--                    ГАСЯЩИЕ ИМПУЛЬСЫ ДЛЯ VGA И VIDEO                091102  --
--------------------------------------------------------------------------------

signal VGA_KGI      : std_logic; -- кадровые гасящие импульсы для VGA
signal VGA_SGI      : std_logic; -- строчные гасящие импульсы для VGA
signal VGA_BLANK    : std_logic; -- гасящие импульсы для VGA

signal VIDEO_KGI    : std_logic; -- кадровые гасящие импульсы для VIDEO
signal VIDEO_SGI    : std_logic; -- строчные гасящие импульсы для VIDEO
signal VIDEO_BLANK  : std_logic; -- гасящие импульсы для VIDEO

--------------------------------------------------------------------------------
--                РЕГИСТР ДЛЯ ЧТЕНИЯ ТОЧКИ В ОЗУ            			 090821  --
--------------------------------------------------------------------------------

signal RD_REG       : std_logic_vector(23 downto 0);

begin

--------------------------------------------------------------------------------
--                            ПРОЦЕССЫ                                        --
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                   НОРМАЛИЗАЦИЯ ВХОДНЫХ СИГНАЛОВ                    090826  --
--------------------------------------------------------------------------------

-- если соответствующая перемычка/тумблер находится в положении ON, 
-- что соответствует логическому нулю, соответствующий сигнал инвертируется.
-- затем код цвета тактируются
--------------------------------------------------------------------------------
RGBI_CLK <= not CLK2 when inverse_f else CLK2; -- нормализация тактовых синхроимпульсов
--------------------------------------------------------------------------------
process (RGBI_CLK, RGB_IN)   
begin
  if (falling_edge(RGBI_CLK)) then -- если спад тактового импульса
      RGB <= RGB_IN;
  end if;
end process;

--------------------------------------------------------------------------------
--              ФОРМИРОВАНИЕ СИГНАЛОВ ДЛЯ СБРОСА СЧЕТЧИКОВ            091223  --
--------------------------------------------------------------------------------
process (CLK, SSI_IN, SSI)
begin

  if (rising_edge(CLK)) then  -- если фронт тактового импульса, переход из 0 в 1
		if (inverse_ssi) then
			SSI   <= not SSI_IN;
		else 
			SSI   <= SSI_IN;
		end if;
      SSI_2 <= not SSI;       -- задержка на такт строчного синхроимпульса
  end if;
end process;

process (KSI, KSI_2, VGA_H, VIDEO_H, KSI_IN, SSI, SSI_2)
begin
  -- выборка состояния кадрового синхроимпульса во время 1/4...1/2 строки VIDEO
  if (rising_edge(VIDEO_H(8)) and VIDEO_H(9)='0') then
		if (inverse_ksi) then
			KSI   <= not KSI_IN;
		else
			KSI   <= KSI_IN;
		end if;
      KSI_2 <= not KSI;       -- задержка кадрового синхроимпульса на строку 
  end if;
end process;

RESET_H <= SSI or SSI_2;      -- если 0, то можно сбрасывать счетчик тактов    
RESET_V <= KSI or KSI_2;      -- если 0, то можно сбрасывать счетчик строк
-- зона для сброса счетчиков, 0 в средней части экрана по-вертикали
RESET_ZONE  <= (not VIDEO_V(7) or VIDEO_V(8)); 

VGA_V_CLK   <= (VGA_H(7)   or VGA_H(8));
VIDEO_V_CLK <= (VIDEO_H(8) or VIDEO_H(9));

--------------------------------------------------------------------------------
--                 УПРАВЛЕНИЕ СЧЕТЧИКАМИ ТАКТОВ В СТРОКАХ             091220  --
--------------------------------------------------------------------------------
process (CLK, DS80, RESET_H, RESET_ZONE, VGA_H_MAX, VGA_H, VIDEO_H)
begin  
  -- максимальное значение счетчика точек VGA 
  if (DS80 = '0') then
      VGA_H_MAX <= "110111111"; -- 447 (895/2) pent
  else 
	   VGA_H_MAX <= "101111111"; -- 383 (767/2) profi
  end if;

  if (falling_edge(CLK)) then          -- иначе, по спаду тактового импульса:

    -- если начало строчного СИ и строка в средней части экрана по-вертикали:
    -- синхронизируем счетчики тактов с входными синхроимпульсами
    if (RESET_H or RESET_ZONE) = '0'  then
      VGA_H     <= (others => '0');    -- обнуляем счетчик тактов VGA
      VIDEO_H   <= (others => '0');    -- обнуляем счетчик тактов VIDEO
      
    else                               -- иначе - автономный счет:
   
      if (VGA_H = VGA_H_MAX) then      -- если последний такт в строке VGA,
        VGA_H   <= (others => '0');    -- обнуляем счетчик тактов VGA
      else
        VGA_H   <= VGA_H + 1;          -- иначе - увеличиваем счетчик тактов
      end if;    

      if (VIDEO_H = (VGA_H_MAX & "1")) then -- если послед. такт в строке VIDEO,
        VIDEO_H <= (others => '0');    -- обнуляем счетчик тактов VGA
      else
        VIDEO_H <= VIDEO_H + 1;        -- иначе - увеличиваем счетчик тактов
      end if;    

   end if;   
  end if;   
end process;

--------------------------------------------------------------------------------
--                 УПРАВЛЕНИЕ СЧЕТЧИКАМИ СТРОК В КАДРЕ                091223  --
--------------------------------------------------------------------------------

process (VGA_V_CLK, RESET_V, VIDEO_V_CLK, VIDEO_V)
begin
--------------------------------------------------------------------------------
-- счетчик строк VGA:
  if (falling_edge(VGA_V_CLK)) then  -- по спаду сигнала увеличения счетч. строк

    -- выходная частота кадров 48/50 Гц
      if (RESET_V) = '0' then        -- если начало кадрового синхроимпульса:
        VGA_V <= (others => '0');    -- обнуляем счетчик строк VGA
      else                           -- иначе 
        VGA_V <= VGA_V   + 1;        -- увеличиваем счетчик строк VGA
      end if;    
  end if;    
--------------------------------------------------------------------------------
-- счетчик строк VIDEO:
  if (falling_edge(VIDEO_V_CLK)) then -- по спаду сигнала увеличения счетч.строк
    if (RESET_V) = '0' then           -- если начало кадрового синхроимпульса:
      VIDEO_V <= (others => '0');     -- обнуляем счетчик строк VIDEO
    else    
      VIDEO_V <= VIDEO_V + 1;         -- увеличиваем счетчик строк VIDEO
    end if;    
  end if;    
-------------------------------------------------------------------------------
end process;

--------------------------------------------------------------------------------
--                ФОРМИРОВАНИЕ ПАРАМЕТРОВ РАЗВЕРТКИ VGA               091223  --
--------------------------------------------------------------------------------
-- строчные синхроимпульсы для VGA:
-- экран спектрума: 768 точек на 608 линий, всего 896 точек на 640 линий.
-- экран профи: 608 точек на 544 линии, всего 768 точек на 624 линии.

-- параметры строчной развертки
-- продолжение предыдущего синхромпульса, потом бланк, потом видимая область экрана между концом ГИ1 и началом ГИ2, потом синхроимпульс

process (DS80)                   
begin
  case DS80 is
 
    when '0' =>   -- "Спектрум"
      -- строчная развертка VGA:
      VGA_SSI1_BGN <= "0000000000"; --   0 - начало 1 строчного СИ
      VGA_SSI1_END <= "0000100110"; --  38 - конец  1 строчного СИ
      VGA_SGI1_END <= "0001001001"; -- 73 - конец  1 строчного ГИ 65 + 48 - 24 - 8 missing
      VGA_SGI2_BGN <= "1101010001"; -- 849 - начало 2 строчного ГИ
      VGA_SSI2_BGN <= "1101111011"; -- 891 - начало 2 строчного СИ
      VGA_SSI2_END <= "1101111111"; -- 895 - конец  2 строчного СИ -- конец лини

    when '1' =>   -- "Профи"
      VGA_SSI1_BGN <= "0000000000"; --   0 - начало 1 строчного СИ
      VGA_SSI1_END <= "0000100010"; --  34 - конец  1 строчного СИ
      VGA_SGI1_END <= "0000111001"; -- 57 -- 141 - конец  1 строчного ГИ 57 + 84 missing = 141!!!
      VGA_SGI2_BGN <= "1011101101"; -- 749 -- 749 - начало 2 строчного ГИ
      VGA_SSI2_BGN <= "1011110101"; -- 757 - начало 2 строчного СИ
      VGA_SSI2_END <= "1011111111"; -- 767 - конец  2 строчного СИ
	
	when others => null;

  end case;
end process;
--------------------------------------------------------------------------------
-- кадровая развертка VGA:

process (DS80)                   
begin
  case DS80 is

    when '0' =>   -- "Спектрум"
--		VGA_KSI_BGN  <= "0000001011"; --  11 - начало кадрового СИ
--		VGA_KSI_END  <= "0000001100"; --  12 - конец  кадрового СИ
--		VGA_KGI1_END <= "0000101100"; --  44 - конец  кадрового ГИ
--		VGA_KGI2_BGN <= "1001110001"; -- 625 - начало кадрового ГИ
		VGA_KSI_BGN  <= "0000010101"; --  21 - начало кадрового СИ
		VGA_KSI_END  <= "0000010110"; --  22 - конец  кадрового СИ
		VGA_KGI1_END <= "0000100001"; --  33 - конец  кадрового ГИ
		VGA_KGI2_BGN <= "1010000000"; -- 640 - начало кадрового ГИ

	when '1' =>   -- "Профи"
		VGA_KSI_BGN  <= "0000001111"; --  15 - начало кадрового СИ
		VGA_KSI_END  <= "0000010000"; --  16 - конец  кадрового СИ
--		VGA_KGI1_END <= "0000101100"; --  44 - конец  кадрового ГИ
		VGA_KGI1_END <= "0000001100"; --  12 - конец  кадрового ГИ
		VGA_KGI2_BGN <= "1001110001"; -- 625 - начало кадрового ГИ
--		VGA_KSI_BGN  <= "0000110010"; --  50 - начало кадрового СИ -- 50 todo 42
--		VGA_KSI_END  <= "0000110011"; --  51 - конец  кадрового СИ -- 51 todo 43
--		VGA_KGI1_END <= "0001100001"; --  97 - конец  кадрового ГИ -- 128 --
--		VGA_KGI2_BGN <= "1001000001"; -- 577 - начало кадрового ГИ -- 624 --		
		-- остается 480 видимых линий, ибо разрешение 640х480, верхний и нижний бордюр не будет видно (уходит в blank)
		
	when others => null;

  end case;
end process;
--------------------------------------------------------------------------------
--                   ФОРМИРОВАНИЕ СТРОЧНЫХ ИМПУЛЬСОВ VGA              091223  --
--------------------------------------------------------------------------------
-- основные строчные синхроимпульсы для VIDEO
VGA_SSI  <= '0' when (VGA_H >= VGA_SSI1_BGN and VGA_H <= VGA_SSI1_END) 
                  or (VGA_H >= VGA_SSI2_BGN and VGA_H <= VGA_SSI2_END) 
                else '1';

-- строчные гасящие импульсы для VIDEO
VGA_SGI  <= '0' when (VGA_H <= VGA_SGI1_END)
                  or (VGA_H >= VGA_SGI2_BGN)
                else '1';

--------------------------------------------------------------------------------
--                   ФОРМИРОВАНИЕ КАДРОВЫХ ИМПУЛЬСОВ VGA              091223  --
--------------------------------------------------------------------------------
-- кадровые синхроимпульсы для VIDEO
VGA_KSI  <= '0' when (VGA_V >= VGA_KSI_BGN) 
                 and (VGA_V <= VGA_KSI_END) 
                else '1';
-- кадровые гасящие импульсы для VIDEO
VGA_KGI  <= '0' when (VGA_V <= VGA_KGI1_END) 
                  or (VGA_V >= VGA_KGI2_BGN )  
                else '1';
                  
--------------------------------------------------------------------------------
--                    ФОРМИРОВАНИЕ СТРОЧНЫХ ИМПУЛЬСОВ VIDEO           091223  --
--------------------------------------------------------------------------------

-- основные строчные синхроимпульсы для VIDEO:

                       -- клон Спектрума (14 МГц)
VIDEO_SSI1 <= '0' when (VIDEO_H > 20 and VIDEO_H < 87 and DS80 = '0')
                       -- Профи (12 МГц)
                    or (VIDEO_H > 17 and VIDEO_H < 75 and ds80 = '1')                
                  else '1';

-- строчные синхроимпульсы - врезки для VIDEO:
                       -- клон Спектрума (14 МГц)
VIDEO_SSI2 <= '0' when (VIDEO_H > 20 and VIDEO_H < 851 and DS80 = '0')
                       -- Профи (12 МГц)
                    or (VIDEO_H > 17 and VIDEO_H < 729 and DS80 = '1')                
                  else '1';

-- строчные гасящие импульсы для VIDEO:
                       -- клон Спектрума (14 МГц)
VIDEO_SGI  <= '0' when (VIDEO_H < 168 and DS80 = '0')
                       -- Профи (12 МГц)
                    or (VIDEO_H < 144 and DS80 = '1')                
                  else '1';

--------------------------------------------------------------------------------
--                   ФОРМИРОВАНИЕ КАДРОВЫХ ИМПУЛЬСОВ VIDEO            091103  --
--------------------------------------------------------------------------------
-- кадровые синхроимпульсы для VIDEO
VIDEO_KSI  <= '0' when VIDEO_V < 4 else '1';

-- кадровые гасящие импульсы для VIDEO
VIDEO_KGI  <= '0' when VIDEO_V < 16 else '1';


--------------------------------------------------------------------------------
--                    ФОРМИРОВАНИЕ СИНХРОСМЕСИ ДЛЯ VIDEO              090820  --
--------------------------------------------------------------------------------
VIDEO_SYNC <= VIDEO_SSI2 when VIDEO_KSI = '0' else VIDEO_SSI1;

--------------------------------------------------------------------------------
--                    ФОРМИРОВАНИЕ СМЕСИ ГАСЯЩИХ ИМПУЛЬСОВ            091025  --
--------------------------------------------------------------------------------
-- гасящие импульсы для VIDEO
VIDEO_BLANK <= VIDEO_KGI and VIDEO_SGI;

--------------------------------------------------------------------------------
--                     VIDEO ОЗУ                										--
--------------------------------------------------------------------------------

LINEBUF: entity work.linebuf
port map (
	address_a => VIDEO_V(0) & VIDEO_H(9 downto 0),
	clock_a 	 => CLK2,
	data_a 	 => RGB,
	wren_a 	 => '1',
	q_a 		 => open,
	
	address_b => (not VIDEO_V(0)) & VGA_H(8 downto 0) & CLK,
	clock_b 	 => VGA_RBGI_CLK,
	data_b 	 => (others => '1'),
	wren_b 	 => '0',
	q_b 		 => RD_REG
);

--------------------------------------------------------------------------------
-- синхронизация гасящих импульсов и вывод синхроимпульсов

process (CLK, VGA_KGI, VGA_SGI, VGA_KSI, VGA_SSI, EN) 
begin
if (rising_edge(CLK)) then  -- если фронт тактового импульса, переход из 0 в 1
      -- гасящие импульсы для VGA
      VGA_BLANK   <= VGA_KGI and VGA_SGI;

		if (EN = '1') then 
			VSYNC_VGA <= VGA_KSI;      -- кадровые синхроимпульсы для VGA
			HSYNC_VGA <= VGA_SSI;      -- строчные синхроимпульсы для VGA
		else 
			VSYNC_VGA <= KSI_IN;
			HSYNC_VGA <= SSI_IN;
		end if;
  end if;
end process;

-- удвоение частоты с помощью задержанного сигнала
VGA_RBGI_CLK <= CLK2;
      
--------------------------------------------------------------------------------
--                      вывод RGBI на разъем VGA                      091024  --
--------------------------------------------------------------------------------
process (VGA_RBGI_CLK, RD_REG, EN) 
begin
  if (rising_edge(VGA_RBGI_CLK)) then  -- если фронт тактового импульса,
	 if (EN = '1') then
		 if (VGA_BLANK = '0') then 
			RGB_O <= (others => '0');
			VGA_BLANK_O <= '0';
		 else 
			RGB_O <= RD_REG;
			VGA_BLANK_O <= '1';
		 end if;
	 else 
		RGB_O <= RGB_IN;
		VGA_BLANK_O <= SSI_IN and KSI_IN;
	 end if;
  end if;
end process;

end RTL;
