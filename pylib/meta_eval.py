from nltk.tokenize import word_tokenize
import string
from similarity.normalized_levenshtein import NormalizedLevenshtein


normalized_levenshtein = NormalizedLevenshtein()


# this function is called by get_evaluation_metric with the purpose of comparing the values of the output and the ones
# of the gold standard.
# input: tuples list with gold standard values (l1), tuples list with output values (l2), type of publication
# output: boolean stating if the two references are the same
def compare_meta(l1, l2, type):
    val = False
    new_l1, new_l2 = [], []

    # clean the dict contents
    count = 0
    while count < 2:
        for tup in [l1, l2][count]:
            sec_pos = []
            for occur in tup[1]:
                if isinstance(occur, list):
                    n_l = []
                    for el in occur:
                        r = match_content(el, tup[0])
                        if isinstance(r, list):
                            n_l.extend(r)
                        else:
                            n_l.append(r)
                    # [new_l1, new_l2][count].append((tup[0], n_l))
                    sec_pos.append(n_l)
                else:
                    # [new_l1, new_l2][count].append((tup[0], match_content(tup[1], tup[0])))
                    sec_pos.append(match_content(occur, tup[0]))

            [new_l1, new_l2][count].append((tup[0], sec_pos))
        count += 1

    # direct check if all the key-values pair are exactly the same
    if new_l1 == new_l2:
        val = True
        reject_l = None
    else:
        res, check = 0, 0
        # check if there are the minimum metadata in common, else they are different and val goes False (unless it is
        # title which represents an exception)
        keys1 = set([tup[0] for tup in l1])
        keys2 = set([tup[0] for tup in l2])
        if keys1 == keys2 and not (type == 'article' or type == 'newspaper'):
            check += 1
            reject_l = None
            for key in keys1:
                res += eval_field(
                    {key: [f[1] for f in new_l1 if f[0] == key][0]},
                    {key: [f[1] for f in new_l2 if f[0] == key][0]}
                )

        elif type == 'article' or type == 'newspaper':
            check += 1
            # if 'monogr-title' in keys1 and not 'monogr-title' in keys2:
            if ('date' in keys1 and not 'date' in keys2) or ('monogr-title' in keys1 and not 'monogr-title' in keys2) \
                    and not ('analytic-title' in keys2 or ('biblScope_unit_volume' in keys2 and 'biblScope_unit_page' in keys2)):
                res += 1
                reject_l = None
            else:
                eval_l = []
                reject_l = []  # counter for article title and volume-pages
                # use keys2 since not all the metadata of keys1 are necessarily present in keys2 (the contrary is true)
                for key in keys2:
                    res = 0
                    res += eval_field(
                        {key: [f[1] for f in new_l1 if f[0] == key][0]},
                        {key: [f[1] for f in new_l2 if f[0] == key][0]}
                    )
                    # if before the last item there is already one wrong, it makes no sense to continue searching
                    if (key == 'date' or key == 'monogr-title') and res == 1:
                        break
                    elif (key == 'analytic-title' or 'volume' in key or 'page' in key) and res == 1:
                        if 'analytic-title' in reject_l or ('volume' in reject_l and 'page' in reject_l) or \
                                (not 'analytic-title' in keys2 and ('volume' in reject_l or 'page' in reject_l)):
                            break
                        else:
                            reject_l.append(key)
                    else:
                        eval_l.append(key)
        else:
            reject_l = None

        if check == 1 and res == 0:
            val = True

    # print(val)
    return val, reject_l


# function to compare single output and gold standard values
def compare_single(t1, t2, type, parser_name):
    out_l = []
    # select both the terms singularly
    for t in [t1, t2]:
        # check if the selected item is a list: in case analyse all the elements separately and return a list
        if isinstance(t, list):
            n_l = []
            for el in t:
                r = match_content(el, t)
                if isinstance(r, list):
                    n_l.extend(r)
                else:
                    n_l.append(r)
            out_l.append(n_l)
        # if it is a string just return the parsed string
        else:
            if parser_name in ['ScienceParse', 'Scholarcy'] and [t1, t2].index(t) == 1 and type in ['forename', 'surname']:
                n_l = []
                for el in t.split(' '):
                    n_l.append(match_content(el, t))
                out_l.append(n_l)
            else:
                out_l.append(match_content(t, type))

    if eval_field({type: [out_l[0]]}, {type: [out_l[1]]}) == 0:
        # print('True')
        return True
    else:
        # print('False')
        return False


def match_content(t, type):
    if t is not None and len(t):
        if type == 'biblScope_unit_page':
            out = clean_pages(t)
        else:
            encoded_string = t.encode("ascii", "ignore")
            decode_string = encoded_string.decode()
            if type == 'date' or 'volume' in type or 'issue' in type:
                out = clean_dates(decode_string)
            elif type == 'ref' or type == 'idno_type_docNumber' or 'doi' in type:
                out = clean_urls(decode_string)
            else:
                out = clean_contents(decode_string)
        # print(out)
        return out
    else:
        return ' '  # it must be a string with a space in order to get the maximum distance


# cleas alphabetical strings
def clean_contents(t):
    tokens = word_tokenize(t)  # tokenise the input text
    tokens = [w.lower() for w in tokens]  # lowercase the tokens
    table = str.maketrans('', '', string.punctuation)  # remove punctuation from each word
    stripped = [w.translate(table) for w in tokens]
    # remove remaining tokens that are not alphabetic
    words = [word for word in stripped if word.isalnum()]
    words = ' '.join(words)
    # print(words)
    return words


# cleans numeric data
def clean_dates(t):
    if '-' in t:
        tokens = t.split('-')
        new_s = [a for a in tokens if len(a) == 4]
        if len(new_s):
            return new_s[0]
        else:
            return [a.lower() for a in tokens]
    else:
        return t


# cleans strings with a mix of numbers, letters and marks
def clean_urls(t):
    t = t.lower()  # lowercase the tokens
    if ' ' in t:
        temp = t.split(' ')
        final = ''.join(temp)
        return final
    else:
        return t


def clean_pages(t):
    # '1-10'
    # '1'
    if not t.isalnum():
        if '-' in t:
            code = '-'
        elif chr(8211) in t:
            code = chr(8211)
        else:
            code = [c for c in t if not c.isalnum()][0]
        tokens = t.split(code)
        new_s = [w.lower() for w in tokens]  # lowercase the tokens if there is any letter for instance in a e-page
        return new_s
    else:
        return t


# input: gold standard dict with field as key and list of all the occurencies as value, output dict with field as key
# and list of all the occurencies as value.
# The function takes every value of the list and compares it to the value of the gold standard. If one of them is true
# it returns 0.
def eval_field(d1, d2):
    # definition of the deltas
    delta = 1  # valid for DOIs and dates
    keys = list(d1.keys())
    if 'title' in keys[0] or 'note' in keys or 'surname' in keys or 'forename' in keys or 'publisher' in keys:
        delta = 0.85
    if 'volume' in keys[0] or 'issue' in keys[0] or 'page' in keys[0] or 'idno_type_docNumber' in keys:
        delta = 0.9
    if 'ref' in keys:
        delta = 0.95

    # return 0 if the two items are the same, otherwise 1
    # specifica per le note
    # differenziare liste e non liste
    found = 1
    if keys[0] == 'date':
        for date1 in d1[keys[0]]:
            for date2 in d2[keys[0]]:
                if normalized_levenshtein.similarity(date1[0], date2[0]) >= delta or \
                        normalized_levenshtein.similarity(date1[1], date2[1]) >= delta:
                    found = 0
                    break

    elif 'DOI' in keys[0]:
        for doi1 in d1[keys[0]]:
            for doi2 in d2[keys[0]]:
                if '10.' in doi1 and '10.' in doi2:
                    suffix1 = doi1.split('10.')[1]
                    suffix2 = doi2.split('10.')[1]
                    if normalized_levenshtein.similarity(suffix1, suffix2) >= delta:
                        prefix1 = doi1.split('10.')[0]
                        prefix2 = doi2.split('10.')[0]
                        if normalized_levenshtein.similarity(prefix1, prefix2) >= delta:
                            found = 0

        '''elif 'monographic-title' in keys[0]:
            tit2 = d2[keys[0]]
            tit1 = d1[keys[0]]
            if len(tit1.split(' ')) == len(tit2.split(' ')):
                if normalized_levenshtein.similarity(i1, i2) >= delta:
                    found = 0'''

    elif 'page' in keys[0] and (len(d1[keys[0]]) and len(d2[keys[0]])) and (len(d1[keys[0]][0]) != len(d2[keys[0]][0])):
        if len(d1[keys[0]][0]) > len(d2[keys[0]][0]):
            a, b = d2[keys[0]], d1[keys[0]]
        else:
            a, b = d1[keys[0]], d2[keys[0]]
        for i2 in a[0]:
            for i1 in b[0]:
                if normalized_levenshtein.similarity(i1, i2) >= delta:
                    found = 0
                    break

    # only the initial of the first forename shall be analysed
    elif 'forename' in keys[0]:
        for i1 in d1[keys[0]]:
            for i2 in d2[keys[0]]:
                try:
                    if normalized_levenshtein.similarity(i1[0], i2[0]) >= delta:
                        found = 0
                except IndexError:
                    print(d1, d2)
                    found = 1

    else:  # per titoli e nomi
        for i1 in d1[keys[0]]:
            for i2 in d2[keys[0]]:
                if normalized_levenshtein.similarity(i1, i2) >= delta:
                    found = 0

    return found


'''clean_contents('This is a long text.')
clean_contents('This shoul%d be a "title" for some peèople.')
clean_contents("Mordivoi, scifonai, non vi avessi visto mai!")
clean_contents('65498476')'''
'''print(nltk.edit_distance(clean_contents('Mordivoi, scifonai, non vi avessi visto mai!'), clean_contents('Mordivoi, scifonai, non vi avessi visto mai! Dico io'), transpositions=False))
print(normalized_levenshtein.similarity(clean_contents('Mordivoi, scifonai, non vi ave/ssi visto mai!'), clean_contents('Mordivoi, scifo/nai, non vi avessi visto mai! cacca')))'''
'''compare_meta({'analytic-title':'This shoul%d be a "title" for some peèople.'}, {'analytic-title':'This should be a "title" for some peèople'}, 'article')
compare_meta({'date':['2011-12-02', '02 December 2011']}, {'date':['2011', '2011']}, 'date')
compare_meta({'date':['2011', '2011a']}, {'date':['2011', '2011a']}, 'date')
compare_meta({'date':['2011', '2011']}, {'date':['', '2011asap']}, 'date')
compare_meta({'ref':'https://pypi.org/project/strsim/#normalized-levenshtein'}, {'ref':'https://pypi.org/project/strsim/#normalized-levenshtein'}, 'ref')
compare_meta({'ref':'https://pypi.org/project/strsim/#normalized-levenshtein'}, {'ref':'https://pypi.org/pr oject/strsim/#normalized-l%| evenshtein'}, 'ref')'''
# match_content('1-10', 'biblScope_unit_page')
# compare_meta([('date', ['2011', '2011']), ('title', 'This is the title of the work.')], [('date', ['2011', '2009']), ('title', 'This is the title of the work.')], 'article')
# compare_single('Janette', 'Salvo', 'forename')
