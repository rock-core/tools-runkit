#ifndef OPERATIONS_TEST_HPP
#define OPERATIONS_TEST_HPP
namespace Test
{
    struct Parameters
    {
        int    set_point;
        double threshold;
    };

    class Opaque
    {
        int set_point;
        double threshold;
    public:
        Opaque(int p = 0, double t = 0)
            : set_point(p), threshold(t) {}
        int    getSetPoint() const { return set_point; }
        double getThreshold() const { return threshold; }
    };
};
#endif
