# If this printf is removed, Octave complains about function/filename mismatch
printf("");

function ret = uint32_to_str (n)
  ret = sprintf("%s", char(
    bitand(bitshift(n, -24), 0xff),
    bitand(bitshift(n, -16), 0xff),
    bitand(bitshift(n, -8), 0xff),
    bitand(bitshift(n, -0), 0xff)
  ));
  assert(length(ret) == 4);
endfunction

assert(strcmp(uint32_to_str(0x68656c6c), "hell"));

function ret = read_uint8(fd)
  ret = fread(fd, 1, "uint8", 0, "b");
endfunction

function ret = read_int16(fd)
  ret = fread(fd, 1, "int16", 0, "b");
endfunction

function ret = read_uint16(fd)
  ret = fread(fd, 1, "uint16", 0, "b");
endfunction

function ret = read_uint32(fd)
  ret = fread(fd, 1, "uint32", 0, "b");
endfunction

function ret = read_int32(fd)
  ret = fread(fd, 1, "int32", 0, "b");
endfunction

function ret = read_date64(fd)
  # https://tchayen.github.io/posts/ttf-file-parsing
  ret = read_uint32(fd) * 0x100000000 + read_uint32(fd);
endfunction

function ret = flag_bit_is_set (flags, bitIndex)
  ret = bitand(bitshift(flags, -bitIndex), 1);
endfunction

filename = "JetBrainsMono-Regular.ttf";
fd = fopen(filename, "r");

sfntVersion = read_uint32(fd);
numTables = read_uint16(fd);
searchRange = read_uint16(fd);
entrySelector = read_uint16(fd);
rangeShift = read_uint16(fd);

tables = struct();

for i = 1:numTables
  tag = uint32_to_str(read_uint32(fd)); # Tag string
  
  table = struct();
  table.checksum = read_uint32(fd);
  table.offset = read_uint32(fd);
  table.length = read_uint32(fd);
  tables.(tag) = table;
endfor

fseek(fd, tables.head.offset);
head = struct();
head.majorVersion = read_uint16(fd);
head.minorVersion = read_uint16(fd);
head.fontRevision = read_int32(fd) / bitshift(1, 16);
head.checksumAdjustment = read_uint32(fd);
head.magicNumber = read_uint32(fd);
head.flags = read_uint16(fd);
head.unitsPerEm = read_uint16(fd);
head.created = read_date64(fd);
head.modified = read_date64(fd);
head.xMin = read_int16(fd);
head.yMin = read_int16(fd);
head.xMax = read_int16(fd);
head.yMax = read_int16(fd);
head.macStyle = read_uint16(fd);
head.lowestRecPPEM = read_uint16(fd);
head.fontDirectionHint = read_int16(fd);
head.indexToLocFormat = read_int16(fd);
head.glyphDataFormat = read_int16(fd);

fseek(fd, tables.maxp.offset);
maxp = struct();
maxp.version = read_int32(fd) / bitshift(1, 16);
maxp.numGlyphs = read_uint16(fd);
maxp.maxPoints = read_uint16(fd);
maxp.maxContours = read_uint16(fd);
maxp.maxCompositePoints = read_uint16(fd);
maxp.maxCompositeContours = read_uint16(fd);
maxp.maxZones = read_uint16(fd);
maxp.maxTwilightPoints = read_uint16(fd);
maxp.maxStorage = read_uint16(fd);
maxp.maxFunctionDefs = read_uint16(fd);
maxp.maxInstructionDefs = read_uint16(fd);
maxp.maxStackElements = read_uint16(fd);
maxp.maxSizeOfInstructions = read_uint16(fd);
maxp.maxComponentElements = read_uint16(fd);
maxp.maxComponentDepth = read_uint16(fd);

fseek(fd, tables.hhea.offset);
hhea = struct();
hhea.version = read_int32(fd) / bitshift(1, 16);
hhea.ascent = read_int16(fd);
hhea.descent = read_int16(fd);
hhea.lineGap = read_int16(fd);
hhea.advanceWidthMax = read_uint16(fd);
hhea.minLeftSideBearing = read_int16(fd);
hhea.minRightSideBearing = read_int16(fd);
hhea.xMaxExtent = read_int16(fd);
hhea.caretSlopeRise = read_int16(fd);
hhea.caretSlopeRun = read_int16(fd);
hhea.caretOffset = read_int16(fd);
# Skip 4 reserved places
read_int16(fd);
read_int16(fd);
read_int16(fd);
read_int16(fd);
hhea.metricDataFormat = read_int16(fd);
hhea.numOfLongHorMetrics = read_uint16(fd);

fseek(fd, tables.hmtx.offset);
hmtx = struct(); # HTMX !!!!!
hmtx.hMetrics = [];
for i = 1:hhea.numOfLongHorMetrics
  data = struct();
  data.advanceWidth = read_uint16(fd);
  data.leftSideBearing = read_int16(fd);
  hmtx.hMetrics = [hmtx.hMetrics; data];
endfor

hmtx.leftSideBearing = [];
for i = 1:maxp.numGlyphs - hhea.numOfLongHorMetrics
  hmtx.leftSideBearing = [hmtx.leftSideBearing; read_int16(fd)];
endfor

fseek(fd, tables.loca.offset);
loca = [];
for i = 1:maxp.numGlyphs+1
  if head.indexToLocFormat == 0
    loca = [loca; read_uint16(fd)];
  else
    loca = [loca; read_uint32(fd)];
  endif
endfor

function ret = read_coordinates (fd, allFlags, numPoints, readingX)
  ret = zeros(1, numPoints);

  offsetSizeFlagBit = 2;
  offsetSignOrSkipBit = 5;
  if readingX
    offsetSizeFlagBit = 1;
    offsetSignOrSkipBit = 4;
  endif
  
  for i = 1:numPoints
    ret(i) = ret(max(1, i - 1));
    flag = allFlags(i);
    # From: https://www.youtube.com/watch?v=SO83KQuuZvg at 8:06
    onCurve = flag_bit_is_set(flag, 0); # TODO: Do something with this
    
    if flag_bit_is_set(flag, offsetSizeFlagBit)
      offset = read_uint8(fd);
      if flag_bit_is_set(flag, offsetSignOrSkipBit)
        ret(i) += offset;
      else
        ret(i) -= offset;
      endif
    elseif !flag_bit_is_set(flag, offsetSignOrSkipBit)
      ret(i) += read_int16(fd);
    endif
  endfor
endfunction

fseek(fd, tables.glyf.offset);
glyf = [];
for i = 1:length(loca) - 1
  multiplier = 1;
  if head.indexToLocFormat == 0
    multiplier = 2;
  endif
  
  locaOffset = loca(i) * multiplier;
  fseek(fd, tables.glyf.offset + locaOffset);
  
  data = struct();
  data.numberOfContours = read_int16(fd);
  data.xMin = read_int16(fd);
  data.yMin = read_int16(fd);
  data.xMax = read_int16(fd);
  data.yMax = read_int16(fd);
  data.allFlags = [];
  data.xCoords = [];
  data.yCoords = [];
  
  if data.numberOfContours > 0
    endPtsOfContours = [];
    for i = 1:data.numberOfContours
      endPtsOfContours = [endPtsOfContours; read_uint16(fd)];
    endfor
    
    instructionsLength = read_uint16(fd);
    fseek(fd, ftell(fd) + instructionsLength); # Skip instructions
    
    numPoints = endPtsOfContours(length(endPtsOfContours)) + 1;
    allFlags = [];
    for i = 1:numPoints
      flag = read_uint8(fd);
      allFlags = [allFlags; flag];
      
      # From: https://www.youtube.com/watch?v=SO83KQuuZvg
      # If REPEAT bit is set, read next byte to determine num copies
      if flag_bit_is_set(flag, 3)
        for r = 1:read_uint8(fd)
          allFlags = [allFlags; flag];
        endfor
      endif
    endfor
    
    #allFlags = allFlags(1:numPoints);
    
    data.allFlags = allFlags;
    data.xCoords = read_coordinates(fd, allFlags, numPoints, true);
    data.yCoords = read_coordinates(fd, allFlags, numPoints, false);
  endif
  glyf = [glyf; data];
endfor

fseek(fd, tables.cmap.offset);
cmap = struct();
cmap.version = read_uint16(fd);
# The ttf parsing blog post im following only thinks about cmap version 0
assert(cmap.version == 0);

cmap.numTables = read_uint16(fd);

cmap.encodingRecords = [];
cmap.glyphIndexMap = struct();

for i = 1:cmap.numTables
  data = struct();
  data.platformID = read_uint16(fd);
  data.encodingID = read_uint16(fd);
  data.offset = read_uint32(fd);
  
  cmap.encodingRecords = [cmap.encodingRecords; data];
endfor

selectedEncodingRecordOffset = -1;
for i = 1:cmap.numTables
  data = cmap.encodingRecords(i);
  isWindowsPlatform = data.platformID == 3 && (data.encodingID == 0 || data.encodingID == 1 || data.encodingID == 10);
  isUnicodePlatform = data.platformID == 0 && (data.encodingID >= 0 && data.encodingID <= 4);
  if isWindowsPlatform || isUnicodePlatform
    selectedEncodingRecordOffset = data.offset;
    break
  endif
endfor

assert(selectedEncodingRecordOffset != -1);

format = read_uint16(fd);
assert(format == 4);

cmap.glyphIndexMap = parseFormat4(fd).glyphIndexMap;

function ret = parseFormat4 (fd)
  ret = struct();
  ret.format = 4;
  ret.length = read_uint16(fd);
  ret.language = read_uint16(fd);
  ret.segCountX2 = read_uint16(fd);
  ret.searchRange = read_uint16(fd);
  ret.entrySelector = read_uint16(fd);
  ret.rangeShift = read_uint16(fd);
  ret.endCode = [];
  ret.startCode = [];
  ret.idDelta = [];
  ret.idRangeOffset = [];
  ret.glyphIndexMap = struct(); # From blog post: "This one is my addition, contains final unicode->index mapping"

  segCount = bitshift(ret.segCountX2, -1);
  for i = 1:segCount
    ret.endCode = [ret.endCode; read_uint16(fd)];
  endfor
  
  read_uint16(fd); # Reserved padding
  
  for i = 1:segCount
    ret.startCode = [ret.startCode; read_uint16(fd)];
  endfor
  
  for i = 1:segCount
    ret.idDelta = [ret.idDelta; read_int16(fd)];
  endfor
  
  idRangeOffsetsStart = ftell(fd);
  
  for i = 1:segCount
    ret.idRangeOffset = [ret.idRangeOffset; read_uint16(fd)];
  endfor
  
  for i = 1:segCount - 1
    glyphIndex = 0;
    endCode = ret.endCode(i);
    startCode = ret.startCode(i);
    idDelta = ret.idDelta(i);
    idRangeOffset = ret.idRangeOffset(i);
    
    for c = startCode:endCode - 1
      if idRangeOffset == 0
        glyphIndex = bitand((c + idDelta), 0xffff);
        ret.glyphIndexMap.(int2str(c)) = glyphIndex;
        continue
      endif
      
      startCodeOffset = (c - startCode) * 2;
      currentRangeOffset = (i-1) * 2;
      
      glyphIndexOffset = idRangeOffsetsStart + currentRangeOffset + idRangeOffset + startCodeOffset;
      fseek(fd, glyphIndexOffset);
      #fseek(fd, ftell(fd) + glyphIndexOffset);
      
      glyphIndex = read_uint16(fd);
      
      if glyphIndex != 0
        glyphIndex = bitand((glyphIndex + idDelta), 0xffff);
      endif
      
      ret.glyphIndexMap.(int2str(c)) = glyphIndex;
    endfor
  endfor
endfunction

function ret = spacingMap (cmap, glyf, hmtx)
  alphabet = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
  
  ret = struct();
  
  for i = 1:length(alphabet)
    try
      index = cmap.glyphIndexMap.(int2str(double(alphabet(i)))) + 1;
    catch
      index = 0 + 1;
    end_try_catch
    printf("Char '%c' maps to %i\n", alphabet(i), index);
    theGlyf = glyf(index);

    new = struct();
    new.index = index;
    new.x = theGlyf.xMin;
    new.y = theGlyf.yMin;
    new.width = theGlyf.xMax - theGlyf.xMin;
    new.height = theGlyf.yMax - theGlyf.yMin;
    new.lsb = hmtx.hMetrics(index).leftSideBearing;
    new.rsb = hmtx.hMetrics(index).advanceWidth - hmtx.hMetrics(index).leftSideBearing - (theGlyf.xMax - theGlyf.xMin);
    new.allFlags = theGlyf.allFlags;
    new.xCoords = theGlyf.xCoords;
    new.yCoords = theGlyf.yCoords;
	
	  ret.(alphabet(i)) = new;
  endfor
endfunction

#disp(tables);
#disp(head);
#disp(maxp);
#disp(hhea);
#disp(hmtx);
#disp(loca);
#disp(glyf);
#disp(cmap);

w = abs(head.xMin - head.xMax);
h = abs(head.yMin - head.yMax);
printf("Glyphbounds is: %iX%i\n", w, h);

fclose(fd);

fontSizeInPixels = 1;
scale = (1 / head.unitsPerEm) - fontSizeInPixels;
myText = "HELLO"; # Spaces turn into cryptocurrency for some reason
posX = 0;
rects = [];

title (sprintf("Text: \"%s\"", myText), "fontsize", 30);
bezierTextYOffset = 1400 * scale;

for i = 1:length(myText)
  spacing = spacingMap(cmap, glyf, hmtx).(myText(i));
  data = struct();
  if i == 0
    data.x = posX + (spacing.x + 0) * scale;
  else
    data.x = posX + (spacing.x + spacing.lsb) * scale;
  endif
  
  data.y = 48 - (spacing.y + spacing.height) * scale - spacing.height;
  data.width = spacing.width * scale;
  data.height = spacing.height * scale;

  if i == 0
    posX += (spacing.width + spacing.rsb) * scale;
  else
    posX += (spacing.lsb + spacing.width + spacing.rsb) * scale;
  endif
  
  hold("on");
  plot(-(spacing.xCoords * scale + data.x), -(spacing.yCoords * scale + data.y), "-b", "linewidth", 4);

  for i = 1:2:max(length(spacing.xCoords), length(spacing.yCoords))
    try
      a = [spacing.xCoords(i), spacing.yCoords(i)];
      b = [spacing.xCoords(i+1), spacing.yCoords(i+1)];
      c = [spacing.xCoords(i+2), spacing.yCoords(i+2)];
    catch
      break
    end_try_catch
    npoints = 10;
    line1 = linspace(a,b, npoints);
    line2 = linspace(b,c, npoints);
    weights = linspace(1, 0, npoints);
    curve = line1 .* weights + line2 .* (1 - weights);
    plot(-(curve(1, :) * scale + data.x), -(curve(2, :) * scale + data.y) + bezierTextYOffset, "-r", "linewidth", 2);
  endfor
  hold("off");

  
  rects = [rects; data];
endfor

for i = 1:length(rects)
  r = rects(i);
  rectangle("Position", -[r.x, r.y, r.width, r.height], "edgecolor", [0, 1, 0]);
  rectangle("Position", -[r.x, r.y - bezierTextYOffset, r.width, r.height], "edgecolor", [0, 1, 0]);
endfor
