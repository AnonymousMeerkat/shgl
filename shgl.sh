#!/bin/sh
# ShGL - Shell bindings for OpenGL


SCRIPTDIR=`dirname $0`


if [ ! -f /usr/include/GL/gl.h ]; then
    echo '/usr/include/GL/gl.h missing...'
    exit 1
fi


if [ ! -d $SCRIPTDIR/gen ]; then
    mkdir $SCRIPTDIR/gen
    mkdir $SCRIPTDIR/gen/macro
    mkdir $SCRIPTDIR/gen/function
fi


shglh_match() {
    grep $@ >/dev/null 2>&1
    return $?
}

shglh_spaces() {
    for i in `seq $1`; do
        echo -n ' '
    done
}

# shglh_casetype ARGTYPE ARGNAME SOURCE FILENAME SPACES
shglh_casetype() {
    case $1 in
        GLint|GLuint|GLenum|GLsizei|GLbitfield)
            shglh_spaces $5 >> $4
            echo 'int '$2' = atoi('$3');' >> $4
            shglh_spaces $5 >> $4
            echo 'shgl_stream_write(sizeof(int), &'$2');' >> $4
            ;;
        GLshort|GLushort)
            shglh_spaces $5 >> $4
            echo 'short '$2' = atoi('$3');' >> $4
            shglh_spaces $5 >> $4
            echo 'shgl_stream_write(sizeof(short), &'$2');' >> $4
            ;;
        GLfloat|GLclampf)
            shglh_spaces $5 >> $4
            echo 'float '$2' = atof('$3');' >> $4
            shglh_spaces $5 >> $4
            echo 'shgl_stream_write(sizeof(float), &'$2');' >> $4
            ;;
        GLdouble|GLclampd)
            shglh_spaces $5 >> $4
            echo 'double '$2' = atod('$3');' >> $4
            shglh_spaces $5 >> $4
            echo 'shgl_stream_write(sizeof(double), &'$2');' >> $4
            ;;
        GLbyte|GLubyte|GLboolean)
            shglh_spaces $5 >> $4
            echo 'shgl_stream_write(1, &'$3');' >> $4
            ;;
        *)
            echo "$1 NOT HANDLED"
            ;;
    esac
}


# shglh_casetype ARGTYPE ARGNAME FILENAME SPACES
shglh_casetype_read() {
    case $1 in
        GLint|GLsizei)
            shglh_spaces $4 >> $3
            echo 'int '$2' = *((int*)shgl_stream_read(sizeof(int)));' >> $3
            ;;
        GLshort)
            shglh_spaces $4 >> $3
            echo 'short '$2' = *((short*)shgl_stream_read(sizeof(short)));' >> $3
            ;;
        GLushort)
            shglh_spaces $4 >> $3
            echo 'unsigned short '$2' = *((short*)shgl_stream_read(sizeof(short)));' >> $3
            ;;
        GLuint|GLenum|GLbitfield)
            shglh_spaces $4 >> $3
            echo 'unsigned int '$2' = *((unsigned int*)shgl_stream_read(sizeof(int)));' >> $3
            ;;
        GLfloat|GLclampf)
            shglh_spaces $4 >> $3
            echo 'float '$2' = *((float)shgl_stream_read(sizeof(float)));' >> $3
            ;;
        GLdouble|GLclampd)
            shglh_spaces $4 >> $3
            echo 'double '$2' = *((double)shgl_stream_read(sizeof(double)));' >> $3
            ;;
        GLbyte)
            shglh_spaces $4 >> $3
            echo 'char '$2' = *((char)shgl_stream_read(1));' >> $3
            ;;
        GLubyte|GLboolean)
            shglh_spaces $4 >> $3
            echo 'unsigned char '$2' = *((unsigned char)shgl_stream_read(1));' >> $3
            ;;
        *)
            echo "$1 NOT HANDLED"
            ;;
    esac
}

#cat /usr/include/GL/gl.h | grep -v -e '^#' -e 'v(' | grep -v -e 'ARB' -e 'OES' -e 'ATI' -e 'MESA' -e 'EXT' | awk 'BEGIN{semi=0}/GLAPI.*;.*$/{print}/GLAPI[^)]*$/{printf $0;semi=1;next}semi==1{printf $0}semi==1&&/);[ ]*$/{printf "\n";semi=0}' | sed 's:GLAPI \([^ ]*\) GLAPIENTRY \([^(]*\)( \(.*\):\1 \2 ( \3:g' | sed 's:\t: :g' | sed 's:  *: :g'
#exit

for i in `grep '#define *GL_' /usr/include/GL/gl.h | awk '{print $2"-"$3}'`; do
    macro=`echo $i | sed 's:\([^-]*\).*:\1:g'`
    macronogl=`echo $i | sed 's:GL_\([^-]*\).*:\1:g'`

    valueraw=`echo $i | sed 's:.*-\(.*\):\1:g'`
    value=`printf '%i' $valueraw`

    filename=$SCRIPTDIR/gen/macro/$macronogl
    srcfilename=$SCRIPTDIR/src/macro/$macronogl


    if [ ! -f $srcfilename ] && [ ! -f $filename ]; then
        echo "int puts(const char*);" > $filename
        echo "void shgl_macro_"$macronogl"() {" >> $filename
        echo "    puts(\""$value"\");" >> $filename
        echo "}" >> $filename
    fi
done


temp=`mktemp`

# Get list of functions
cat /usr/include/GL/gl.h |
    # Remove preprocessor directives and extensions
    grep -v -e '^#' -e 'ARB' -e 'OES' -e 'ATI' -e 'MESA' -e 'EXT' |
    awk '
BEGIN {
    semi = 0;
}

/GLAPI.*;.*$/ {
    print;
}

/GLAPI[^)]*$/ {
    printf $0;
    semi = 1;
    next;
}

semi == 1 {
    printf $0;
}

semi == 1 && /);[ ]*$/ {
    printf "\n";
    semi = 0;
}' |
    sed 's:const::g' | # Const is unnecessary
    sed 's:/\*[^/]*\*/::g' | # Remove comments
    sed 's: \*:\* :g' | # GLshort *v => GLshort* v
    sed ':glGet.*\*:d' | # Delete Get functions with pointers, those are to be made manually (they're special cases)
    # GLAPI void GLAPIENTRY glEnable( GLenum cap ); => void glEnable ( GLenum cap );
    sed 's:GLAPI *\([^ ]*\) *GLAPIENTRY *\([^(]*\)( *\(.*\):\1 \2 ( \3:g' |
    sed 's:\t: :g' |
    sed 's:  *:+:g' | # In order to be able to iterate through
    sed 's:+);$::g' | # No useful reason for the end );
    grep -v '\*[^,(]*,' > $temp

for i in `cat $temp`; do
    type=`echo $i | cut -d '+' -f 1`
    name=`echo $i | cut -d '+' -f 2`
    namenogl=`echo $name | sed 's:^gl::g'`
    args=`echo $i | cut -d '+' -f 4- | sed 's:+: :g'`

    filename=$SCRIPTDIR/gen/function/$namenogl
    srcfilename=$SCRIPTDIR/src/function/$namenogl

    echo "$type $name($args);"

    # If there is already a source file (e.g. special cases like glGenBuffers), don't make a file
    # if not, create it. parse the arguments, send "blah\0encodedarg1encodedarg2" via socket.
    # wait for reply if non-void and turn into char*

    ### Client

    outtype="void"
    if [ "$type" != "void" ]; then
        outtype="unsigned char*"
    fi

    usestdout=0
    if echo $namenogl | shglh_match '^Ge[nt]'; then
        usestdout=1
        outtype="unsigned char*"
    fi

    haspointer=0
    if echo $args | shglh_match '\*'; then
        haspointer=1
    fi

    echo 'int puts(const char*);' > $filename
    echo "void shgl_function_"$namenogl"(char** argv) {" >> $filename
    echo '    shgl_stream_write('`expr 1 + \`expr length $namenogl\``', "'$namenogl'");' >> $filename


    argcount=0
    for j in `echo $args | sed 's: :+:g' | sed 's:,+*: :g'`; do
        argtype=`echo $j | cut -d '+' -f 1`
        argname=`echo $j | cut -d '+' -f 2`

        if [ "$argtype" == "void" ]; then
            break;
        fi

        if echo $argtype | shglh_match '\*'; then
            break;
        fi

        shglh_casetype $argtype "arg"$argcount "argv["$argcount"]" $filename 4

        argcount=`expr $argcount + 1`
    done

    if [ $haspointer -eq 1 ] && [ $usestdout -eq 0 ]; then
        echo '    unsigned int s;' >> $filename
        echo '    unsigned char* text = shgl_stdin(&s);' >> $filename
        echo '    shgl_stream_write(sizeof(unsigned int), &s);' >> $filename

        if echo $argtype | shglh_match -E -e 'GL.?byte.*' -e 'GLvoid.*'; then
            echo '    shgl_stream_write(s, text);' >> $filename
        else
            echo '    char* in_ch = strtok(text, " \t\n\r\v");' >> $filename
            echo '    while (in_ch != NULL) {' >> $filename
            shglh_casetype `echo $argtype | sed 's:\*::g'` "argp" "in_ch" $filename 8
            echo '        in_ch = strtok(NULL, " \t\n\r\v");' >> $filename
            echo '    }' >> $filename
        fi
    fi

    if [ "$outtype" != "void" ]; then
        echo '    puts(shgl_stream_read());' >> $filename
    fi

    echo '}' >> $filename

    ### Server

    echo 'void shgl_function_server_'$namenogl'() {' >> $filename

    argcount=0
    for j in `echo $args | sed 's: :+:g' | sed 's:,+*: :g'`; do
        argtype=`echo $j | cut -d '+' -f 1`
        argname=`echo $j | cut -d '+' -f 2`

        if [ "$argtype" == "void" ]; then
            break;
        fi

        if echo $argtype | shglh_match '\*'; then
            break;
        fi

        shglh_casetype_read $argtype "arg"$argcount $filename 4

        argcount=`expr $argcount + 1`
    done

    if [ $haspointer -eq 1 ] && [ $usestdout -eq 0 ]; then
        echo '    unsigned int s = *((int)shgl_stream_read(sizeof(size_t)));' >> $filename
        echo '    void* data = shgl_stream_read(s);' >> $filename
    elif [ $haspointer -eq 1 ] && [ $usestdout -eq 1 ]; then
        echo '    void* ret;' >> $filename
    fi


    echo -n '    ' >> $filename

    if [ "$outtype" != "void" ] && [ "$type" != "void" ]; then
        echo -n $type' ret = ' >> $filename
    fi

    echo -n $name'(' >> $filename


    argcount=0
    for j in `echo $args | sed 's: :+:g' | sed 's:,+*: :g'`; do
        argtype=`echo $j | cut -d '+' -f 1`
        argname=`echo $j | cut -d '+' -f 2`

        if [ "$argtype" == "void" ]; then
            break;
        fi

        if [ $argcount -ne 0 ]; then
            echo -n ', ' >> $filename
        fi

        if echo $argtype | shglh_match '\*'; then
            if [ $usestdout -eq 0 ]; then
                echo -n 'data' >> $filename
            else
                echo -n '&ret' >> $filename
            fi

        else
            echo -n 'arg'$argcount >> $filename
        fi

        argcount=`expr $argcount + 1`
    done

    echo ');' >> $filename

    # Special case
    if [ "$name" == "glGenTextures" ]; then
        echo '    for (int i = 0; i < arg0; i++) {' >> $filename
        echo '        char encoded[30];' >> $filename
        echo '        sprintf(encoded, "%u", ret[i]);' >> $filename
        echo '        if ((i + 1) < arg0) {' >> $filename
        echo '            strcat(encoded, " ");' >> $filename
        echo '        }' >> $filename
        echo '        shgl_stream_write(strlen(encoded), encoded);' >> $filename
        echo '    }' >> $filename
    elif [ "$type" != "void" ]; then
        echo '    char encoded[30];' >> $filename
        case $type in
            GLint|GLsizei)
                echo '    sprintf(encoded, "%i", ret);' >> $filename
                ;;
            GLuint|GLenum|GLbitfield)
                echo '    sprintf(encoded, "%u", ret);' >> $filename
                ;;
            GLfloat|GLdouble|GLclampf|GLclampd)
                echo '    sprintf(encoded, "%f", ret);' >> $filename
                ;;
            GLbyte|GLubyte|GLboolean)
                echo '    sprintf(encoded, "%c", ret);' >> $filename
                ;;
            GLbyte\*|GLubyte\*)
                echo '    sprintf(encoded, "%s", ret);' >> $filename
                ;;
            *)
                echo "$type NOT HANDLED(2)"
                ;;
        esac
        echo '    shgl_stream_write(strlen(encoded, encoded);' >> $filename
    fi

    echo '}' >> $filename
done

rm -f $temp
