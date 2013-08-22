require "quarto/plugin"

module Quarto
  class Prince < Plugin
    module BuildExt
      fattr(:prince)
    end

    fattr(:cover_image)

    def enhance_build(build)
      build.deliverable_files << pdf_file
      build.extend(BuildExt)
      build.prince = self
    end

    def define_tasks
      task :deliverables => :pdf

      desc "Build a PDF with PrinceXML"
      task :pdf => :"prince:pdf"

      namespace :prince do
        task :pdf => pdf_file
      end

      file pdf_file => [prince_master_file, main.assets_file] do |t|
        mkdir_p t.name.pathmap("%d")
        sh *%W[prince #{prince_master_file} -o #{t.name}]
      end

      file prince_master_file => [main.master_file, toc_file, stylesheet] do |t|
        create_prince_master_file(prince_master_file, main.master_file, stylesheet)
      end

      file toc_file => [main.master_file, prince_dir] do |t|
        generate_cmd = "pandoc --table-of-contents --standalone #{main.master_file}"
        toc_xpath    = "//*[@id='TOC']"
        extract_cmd  = %Q(xmlstarlet sel -I -t -c "#{toc_xpath}")
        sh "#{generate_cmd} | #{extract_cmd} > #{t.name}"
      end

      file stylesheet => pdf_stylesheets do |t|
        sh "cat #{pdf_stylesheets} > #{t.name}"
      end

      file font_stylesheet do |t|
        puts "generate #{t.name}"
        open(t.name, 'w') do |f|
          main.fonts.each do |font|
            f.puts(font.to_font_face_rule(embed: true))
          end
        end
      end

      directory prince_dir
    end

    def pdf_file
      "#{main.deliverable_dir}/#{main.name}.pdf"
    end

    def prince_master_file
      "#{main.master_dir}/prince_master.xhtml"
    end

    def toc_file
      "#{main.build_dir}/prince/toc.xml"
    end

    def stylesheet
      "#{prince_dir}/styles.css"
    end

    def pdf_stylesheets
      main.stylesheets.applicable_to(:pdf).master_files + FileList[font_stylesheet]
    end

    def font_stylesheet
      "#{prince_dir}/fonts.css"
    end

    def prince_dir
      "#{main.build_dir}/prince"
    end

    def create_prince_master_file(prince_master_file, master_file, stylesheet)
      puts "create #{prince_master_file} from #{master_file}"
      doc = open(master_file) { |f|
        Nokogiri::XML(f)
      }
      body_elt = doc.root.at_css("body")
      first_child = body_elt.first_element_child
      first_child.before("<div class='frontcover'></div>")
      first_child.before(File.read(toc_file))
      doc.at_css("#TOC").first_element_child.before("<h1>Table of Contents</h1>")
      doc.css("link[rel='stylesheet']").remove
      doc.at_css("head").add_child(
        doc.create_element("style") do |elt|
          elt["type"] = "text/css"
          elt.content = File.read(stylesheet)
        end)
      open(prince_master_file, 'w') do |f|
        doc.write_xml_to(f)
      end
    end
  end
end
