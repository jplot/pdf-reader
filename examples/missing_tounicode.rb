#!/usr/bin/env ruby
# coding: utf-8

# Rebuild the ToUnicode CMap of subsetted fonts that lost it.
#
# Some producers strip the ToUnicode CMap when they rewrite a PDF
# (Ghostscript does when it re-subsets embedded fonts): the document still
# renders, but text extraction returns replacement characters. When the
# original font can be identified, the mapping is recoverable: subsetters
# copy glyph outlines byte for byte and only renumber glyph ids, so each
# subset glyph outline, matched against a reference copy of the SAME
# VERSION of the font, identifies its codepoint exactly.
#
# This example supplies such a handler through the :missing_tounicode
# option. To adapt it, provide:
#
#   - your reference fonts (REFERENCES: basefont pattern => fontRevision
#     label => file, resolved against the fonts directory). The version
#     matters: outlines are only equal between identical versions, and
#     head.fontRevision survives subsetting;
#   - your charset (ALPHABET: the codepoints your documents can contain).
#     It also arbitrates homoglyphs: most fonts give cyrillic а the very
#     same outline as latin a, the alphabet decides which one wins.
#
# The default configuration below matches French documents typeset in
# Source Sans Pro and Montserrat (both freely redistributable, OFL).
#
# Requires ttfunk with glyph outline support (prawnpdf/ttfunk#122).
#
# Usage: missing_tounicode.rb somefile.pdf [fonts_directory]

require 'pdf/reader'
require 'ttfunk'
require 'digest'

module MissingToUnicode
  class Handler

    ALPHABET = (
      (0x20..0x7E).to_a +
      'ÀÂÄÇÈÉÊËÎÏÔÖÙÛÜŸàâäçèéêëîïôöùûüÿŒœÆæ'.codepoints +
      '€£¥°±×÷§¶«»‹›’“”•—–…‰≤≥≠´`¹²³⁰⁄'.codepoints
    ).uniq

    REFERENCES = {
      /\ASourceSansPro-Black(,Bold)?-Identity-H\z/ => { '2.021' => 'SourceSansPro-Black.ttf' },
      /\ASourceSansPro-Regular(,Bold)?-Identity-H\z/ => { '2.021' => 'SourceSansPro-Regular.ttf' },
      /\ASourceSansPro-Bold(,Bold)?-Identity-H\z/ => { '2.021' => 'SourceSansPro-Bold.ttf' },
      /\ASourceSansPro-Light(,Bold)?-Identity-H\z/ => { '2.021' => 'SourceSansPro-Light.ttf' },
      /\ASourceSansPro-SemiBold(,Bold)?-Identity-H\z/ => { '2.021' => 'SourceSansPro-Semibold.ttf' },
      /\AMontserrat-ExtraBold(,Bold)?-Identity-H\z/ => { '7.200' => 'Montserrat-ExtraBold.ttf' },
    }

    def initialize(alphabet: ALPHABET, references: REFERENCES, fonts_dir: Dir.pwd)
      @alphabet = alphabet.dup.freeze
      @references = references.dup.freeze
      @fonts_dir = fonts_dir
      @reference_index = {}
    end

    # The option's contract: called once per text-converting font that
    # declares no ToUnicode CMap, with the font, its raw dictionary and the
    # document's objects. Return replacement CMap data, or nil to leave the
    # font unchanged.
    def call(font, dictionary, objects)
      versions = reference_for(font.basefont)
      return nil if versions.nil?

      binary = embedded_font_program(objects, dictionary)
      return nil if binary.nil?

      mapping = reconstruct(binary, versions)
      cmap_stream(mapping) if mapping && mapping.any?
    end

    private

    def reference_for(basefont)
      name = basefont.to_s.sub(/\A[A-Z]{6}\+/, '')
      versions = @references.find { |pattern, _| pattern.match?(name) }
      return nil if versions.nil?

      versions.last.transform_values { |file| File.join(@fonts_dir, file) }
    end

    def embedded_font_program(objects, dictionary)
      descendants = objects.deref(dictionary[:DescendantFonts])
      descendant = descendants && objects.deref(descendants.first)
      descriptor = descendant && objects.deref(descendant[:FontDescriptor])
      stream = descriptor && descriptor[:FontFile2]

      stream && objects.deref(stream).unfiltered_data
    end

    # The reference is selected by the subset's head.fontRevision: outline
    # equality only exists between identical versions of a font.
    def reconstruct(subset_binary, versions)
      subset = TTFunk::File.new(subset_binary)
      label = format('%.3f', subset.header.font_revision / 65_536.0)
      path = versions[label]
      if path.nil?
        $stderr.puts "unknown font version #{label} (references: #{versions.keys.join(', ')})"
        return nil
      end

      signatures = @reference_index[path] ||= build_reference_index(path)
      (1...subset.maximum_profile.num_glyphs).each_with_object({}) do |gid, mapping|
        contours = contours_of(subset, gid)
        next if contours.empty?

        codepoint = signatures[signature(contours)]
        mapping[gid] = codepoint if codepoint
      end
    end

    def build_reference_index(path)
      font = TTFunk::File.open(path)
      cmap = font.cmap.unicode.first
      @alphabet.each_with_object({}) do |codepoint, index|
        gid = cmap[codepoint]
        next unless gid && gid > 0

        contours = contours_of(font, gid)
        next if contours.empty?

        # first-in-alphabet wins when two codepoints share an outline
        index[signature(contours)] ||= codepoint
      end
    end

    def contours_of(font, gid)
      font.glyph_outlines.contours_for(gid).map { |contour|
        contour.map { |point| [point.x, point.y, point.on_curve] }
      }
    rescue TTFunk::Error
      []
    end

    def signature(contours)
      Digest::SHA256.digest(Marshal.dump(contours))
    end

    # Identity-H character codes are two bytes wide, hence the <0000> <FFFF>
    # codespace and four-digit source codes.
    def cmap_stream(mapping)
      pairs = mapping.map { |gid, codepoint|
        utf16 = codepoint.chr(Encoding::UTF_8).encode(Encoding::UTF_16BE).unpack("H*").first.upcase
        format("<%04X> <%s>", gid, utf16)
      }
      blocks = pairs.each_slice(100).map { |slice|
        "#{slice.size} beginbfchar\n#{slice.join("\n")}\nendbfchar"
      }
      <<~CMAP
        /CIDInit /ProcSet findresource begin
        12 dict begin
        begincmap
        /CIDSystemInfo <</Registry (Adobe) /Ordering (UCS) /Supplement 0>> def
        /CMapName /Adobe-Identity-UCS def
        /CMapType 2 def
        1 begincodespacerange
        <0000> <FFFF>
        endcodespacerange
        #{blocks.join("\n")}
        endcmap
        CMapName currentdict /CMap defineresource pop
        end
        end
      CMAP
    end
  end
end

if __FILE__ == $0
  if ARGV.empty?
    $stderr.puts "Usage: #{File.basename(__FILE__)} somefile.pdf [fonts_directory]"
    exit 1
  end

  handler = MissingToUnicode::Handler.new(fonts_dir: ARGV[1] || Dir.pwd)

  PDF::Reader.open(ARGV[0], missing_tounicode: handler) do |reader|
    reader.pages.each do |page|
      puts page.text
    end
  end
end
