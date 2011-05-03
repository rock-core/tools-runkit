#ifndef CONFIGURATION_TYPES_HPP
#define CONFIGURATION_TYPES_HPP 

#include <string>
#include <vector>

enum Enumeration
{
    First,
    Second,
    Third
};

struct ArrayOfArrayElement
{
    Enumeration enm;
    int intg;
    std::string str;
    double fp;
};

struct ArrayElement
{
    Enumeration enm;
    int intg;
    std::string str;
    double fp;

    ArrayOfArrayElement compound;

    std::vector<int> simple_container;
    std::vector<ArrayOfArrayElement> complex_container;
    int simple_array[10];
    ArrayOfArrayElement complex_array[10];
};

struct ComplexStructure
{
    Enumeration enm;
    int intg;
    std::string str;
    double fp;

    ArrayElement compound;

    std::vector<int> simple_container;
    int simple_array[10];

    std::vector<ArrayElement> vector_of_compound;
    std::vector< std::vector<ArrayElement> > vector_of_vector_of_compound;
    ArrayElement array_of_compound[10];
    std::vector<ArrayElement> array_of_vector_of_compound[10];
};

#endif
