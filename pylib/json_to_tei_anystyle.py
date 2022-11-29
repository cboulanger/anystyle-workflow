import json as JS
from lxml.etree import QName
from lxml import etree
import os.path
from generate_new_xml import generate_xml, get_time, add_to_xml
from retrieve_jats_metadata import create_standard_reference
import sys


# to be fixed once we figure out how to move (currently interpreted venue as title) at the time
# of comparison, only in the case of science parse, you will do a double check to see if the title
# of the monograph matches the title of the analytic and the authors are the same.
# If so, equality is ascertained. (translation of original Italian comment)
def create_citation(metadata_list, analyt_node, mono_node, imprint_node, series_node):
    title = venue = year = volume = issue = page_range = publisher = pubplace = uri = doi = series = 0

    for coupled_meta in metadata_list:
        if analyt_node is None:
            analyt_node = mono_node
# CHECK PER PARTICLE
        if (coupled_meta[0] == 'author' or coupled_meta[0] == 'editor') and 'others' not in coupled_meta[1].keys():  # and len(coupled_meta) > 0:
            if coupled_meta[0] == 'author':
                node = analyt_node
            else:
                node = mono_node
            author_node = etree.SubElement(node, coupled_meta[0])
            if 'family' in coupled_meta[1].keys() or 'given' in coupled_meta[1].keys():
                persname_element = etree.SubElement(author_node, 'persName')
            else:  # in case the key is 'literal'
                persname_element = author_node

            for key in coupled_meta[1].keys():
                if key == 'family':
                    new_node = 'surname'
                else:
                    new_node = 'forename'
                etree.SubElement(persname_element, new_node).text = coupled_meta[1][key]

        elif coupled_meta[0] == 'title':  # and title == 0:
            if analyt_node == mono_node:
                analyt_node, title = create_standard_reference(analyt_node, 'title', None, None, coupled_meta[1], title)
            else:
                analyt_node, title = create_standard_reference(analyt_node, 'title', ['level'], ['a'], coupled_meta[1], title)

        elif coupled_meta[0] == 'container-title':  # and venue == 0:
            mono_node, source = create_standard_reference(mono_node, 'title', None, None, coupled_meta[1], venue)

        elif coupled_meta[0] == 'collection-title':  # and series == 0:
            series_node, series = create_standard_reference(series_node, 'title', ['level'], ['s'], coupled_meta[1], series)

        elif coupled_meta[0] == 'date':  # and year == 0:
            try:
                date = get_time(str(coupled_meta[1]))
            except ValueError as err:
                sys.stderr.write(str(err) + f". Full reference: {JS.dumps(metadata_list)}\n")
                date = ""
            imprint_node, year = create_standard_reference(imprint_node, 'date', ['when'], [date], str(coupled_meta[1]), year)

        elif coupled_meta[0] == 'volume':  # and volume == 0:
            if series_node is None:
                imprint_node, volume = create_standard_reference(imprint_node, 'biblScope', ['unit'], ['volume'],
                                                                 coupled_meta[1], volume)
            else:
                series_node, volume = create_standard_reference(series_node, 'biblScope', ['unit'], ['volume'],
                                                                 coupled_meta[1], volume)

        elif coupled_meta[0] == 'issue':  # and issue == 0:
            imprint_node, issue = create_standard_reference(imprint_node, 'biblScope', ['unit'], ['issue'], coupled_meta[1], issue)

        elif coupled_meta[0] == 'publisher':  # and publisher == 0:
            imprint_node, publisher = create_standard_reference(imprint_node, 'publisher', None, None, coupled_meta[1], publisher)

        elif coupled_meta[0] == 'location':  # and pubplace == 0:
            imprint_node, pubplace = create_standard_reference(imprint_node, 'pubPlace', None, None, coupled_meta[1], pubplace)

        elif coupled_meta[0] == 'pages':  # and page_range == 0:
            imprint_node, page_range = create_standard_reference(imprint_node, 'biblScope', ['unit'], ['page'], coupled_meta[1], page_range)

        elif coupled_meta[0] == 'doi':
            analyt_node, doi = create_standard_reference(analyt_node, 'idno', ['type'], ['DOI'], coupled_meta[1], doi)

        elif coupled_meta[0] == 'url':
            mono_node, uri = create_standard_reference(mono_node, 'ref', ['target'], [coupled_meta[1]], coupled_meta[1], uri)

        elif coupled_meta[0] == 'genre' or coupled_meta[0] == 'note':
            mono_node, uri = create_standard_reference(mono_node, 'note', None, None, coupled_meta[1], uri)

        else:
            pass
            #print("Ignoring " + str(coupled_meta))


def add_listbibl(tree, cit_id, metadata_list, analytic_var, series_var, type):
    root = tree.getroot()

    # create listBibl with respective id
    listbibl_element = etree.SubElement(root[0][0], 'biblStruct')
    listbibl_element.attrib[QName("http://www.w3.org/XML/1998/namespace", "id")] = "b"+str(cit_id)
    listbibl_element.attrib["type"] = type
    # create sections analytic and/or monograph
    analyt_node, series_node = None, None
    if analytic_var:
        analyt_node = etree.SubElement(listbibl_element, 'analytic')
    mono_node = etree.SubElement(listbibl_element, 'monogr')
    imprint_node = etree.SubElement(mono_node, 'imprint')
    if series_var:
        series_node = etree.SubElement(listbibl_element, 'series')
    # call the function create_citations to fill the sections
    create_citation(metadata_list, analyt_node, mono_node, imprint_node, series_node)


def anystyle_parser(infile, outfile):
    print(infile)
    try:
        generate_xml(outfile)
        pub_list = ['article', 'chapter', 'paper-conference']  # cases in which analytic node is created

        # load the file and check if there are references in list
        with open(infile, encoding="utf8") as json_file:
            data = JS.load(json_file)
            if len(data):
                pass
                # print("references: ", data)
            else:
                raise RuntimeError("No bibliographic section found")

            # check and list the metadata present in the input json file
            outtree = etree.parse(outfile)
            for ref in data:
                all_meta = []
                analytic_var, series_var = False, False
                keys = ref.keys()
                for field in keys:
                    # check if the reference type allows to create the analytic section or not
                    if field == 'type' and ref[field] in pub_list:
                        analytic_var = True
                    # separate the metadata so that in the creation phase they are ready to be analysed
                    elif field != 'type':
                        if field == 'collection-title':
                            series_var = True
                        if type(ref[field]) is list:
                            for value in ref[field]:
                                all_meta.append((field, value))
                        elif ref[field]:
                            all_meta.append((field, ref[field]))
                        # the fields, if not present should not be identified, else counted as an empty data
                        else:
                            all_meta.append((field, ""))
                add_listbibl(outtree, data.index(ref), all_meta, analytic_var, series_var, ref['type'])

        add_to_xml(outtree, outfile)

    except FileNotFoundError:
        raise FileExistsError(f"File '{infile}' does not exist.")
