// G-SA1 module features: the registry and what the module does with it (gsa1_feature.hpp).
#include "gsa1_feature.hpp"

#include <algorithm>
#include <cstring>
#include <exception>
#include <string>
#include <vector>

#include "gsa1_module_internal.hpp"

namespace gsa1 {

namespace {

Feature *&head()
{
    static Feature *h = nullptr;     // a function-local static: registrars of any file may run first
    return h;
}

// the features whose functions went into the gsa1 table (open_features), for the close and shutdown hooks
std::vector<Feature *> &opened()
{
    static std::vector<Feature *> v;
    return v;
}

bool lower_alnum(char c) { return (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'; }

bool valid_feature_name(const char *n)
{
    if (!n || !(n[0] >= 'a' && n[0] <= 'z')) {
        return false;
    }
    size_t len = std::strlen(n);
    if (len > 32) {
        return false;
    }
    for (size_t i = 0; i < len; i++) {
        if (!lower_alnum(n[i])) {
            return false;
        }
    }
    return true;
}

bool valid_function_name(const char *n)
{
    if (!n || !n[0] || std::strlen(n) > 64 || (n[0] >= '0' && n[0] <= '9')) {
        return false;
    }
    for (const char *p = n; *p; p++) {
        char c = *p;
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_')) {
            return false;
        }
    }
    return true;
}

std::vector<Feature *> by_close_order(const std::vector<Feature *> &in)
{
    std::vector<Feature *> v = in;
    std::stable_sort(v.begin(), v.end(), [](const Feature *a, const Feature *b) {
        if (a->close_priority != b->close_priority) {
            return a->close_priority < b->close_priority;
        }
        return std::strcmp(a->name, b->name) < 0;
    });
    return v;
}

void push_error(GarrysMod::Lua::ILuaBase *L, int et, int &n, const std::string &msg)
{
    L->PushNumber(++n);
    L->PushString(msg.c_str(), (unsigned int)msg.size());
    L->RawSet(et);
}

}  // namespace

FeatureRegistrar::FeatureRegistrar(Feature &f)
{
    Feature **pp = &head();
    while (*pp) {
        if (*pp == &f) {
            return;
        }
        pp = &(*pp)->next;
    }
    f.next = nullptr;
    *pp = &f;
}

Feature *feature_list() { return head(); }

size_t feature_count()
{
    size_t n = 0;
    for (Feature *f = head(); f; f = f->next) {
        n++;
    }
    return n;
}

int open_features(GarrysMod::Lua::ILuaBase *L, int t)
{
    namespace LT = GarrysMod::Lua::Type;
    opened().clear();
    std::vector<Feature *> all;
    for (Feature *f = head(); f; f = f->next) {
        all.push_back(f);
    }
    std::stable_sort(all.begin(), all.end(), [](const Feature *a, const Feature *b) {
        return std::strcmp(a->name ? a->name : "", b->name ? b->name : "") < 0;
    });
    L->CreateTable();
    int ft = L->Top();
    L->CreateTable();
    int et = L->Top();
    int nerr = 0;
    std::vector<std::string> names;
    for (Feature *f : all) {
        std::string name = f->name ? f->name : "";
        std::string why;
        if (!valid_feature_name(f->name)) {
            why = "a feature's name must be [a-z][a-z0-9_]*, at most 32 characters";
        } else if (f->version < 1) {
            why = "its version must be 1 or more";
        } else if (std::find(names.begin(), names.end(), name) != names.end()) {
            why = "a feature of this name is registered already";
        } else if (!f->fns && f->nfns > 0) {
            why = "no function array";
        }
        if (!why.empty()) {
            push_error(L, et, nerr, "feature \"" + name + "\": " + why + ": not registered");
            continue;
        }
        names.push_back(name);
        for (size_t i = 0; i < f->nfns && f->fns[i].name; i++) {
            const FeatureFn &fn = f->fns[i];
            if (!fn.fn || !valid_function_name(fn.name)) {
                push_error(L, et, nerr, "feature " + name + ": function \"" + fn.name + "\": not a valid name or no "
                                        "function: left out");
                continue;
            }
            L->PushString(fn.name);
            L->RawGet(t);
            bool taken = !L->IsType(-1, LT::Nil);
            L->Pop();
            if (taken) {
                push_error(L, et, nerr, "feature " + name + ": gsa1." + fn.name + " exists already: not replaced");
                continue;
            }
            L->PushString(fn.name);
            L->PushCFunction(fn.fn);
            L->RawSet(t);
        }
        mod::raw_num(L, ft, f->name, f->version);
        opened().push_back(f);
    }
    L->PushString("FEATURES");
    L->Push(ft);
    L->RawSet(t);
    L->PushString("FEATURE_ERRORS");
    L->Push(et);
    L->RawSet(t);
    // the open hooks, by name, with the gsa1 table; a hook must leave the stack as it found it
    for (Feature *f : opened()) {
        if (!f->open) {
            continue;
        }
        int top = L->Top();
        std::string err;
        try {
            f->open(L, t);
        } catch (const std::exception &e) {
            err = e.what();
        } catch (...) {
            err = "unknown exception";
        }
        if (L->Top() > top) {
            L->Pop(L->Top() - top);
            if (err.empty()) {
                err = "it left values on the Lua stack";
            }
        }
        if (!err.empty()) {
            push_error(L, et, nerr, std::string("feature ") + f->name + ": open: " + err);
        }
    }
    L->Pop(2);     // ft, et
    return (int)opened().size();
}

void shutdown_features()
{
    for (Feature *f : by_close_order(opened())) {
        if (f->shutdown) {
            try {
                f->shutdown();
            } catch (...) {
            }
        }
    }
}

void close_features(GarrysMod::Lua::ILuaBase *L)
{
    std::vector<Feature *> v = by_close_order(opened());
    opened().clear();
    for (Feature *f : v) {
        if (f->close) {
            int top = L->Top();
            try {
                f->close(L);
            } catch (...) {
            }
            if (L->Top() > top) {
                L->Pop(L->Top() - top);
            }
        }
    }
}

}  // namespace gsa1
