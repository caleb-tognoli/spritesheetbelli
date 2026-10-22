//! Godot's sort (`SortArray` in core/templates/sort_array.h), step for step: it isn't
//! stable, so sorting with another algorithm would order ties differently from
//! `Array.sort_custom`.

const INTROSORT_THRESHOLD: usize = 16;

/// Sorts `items` as `Array.sort_custom` would with `less`
pub fn sort_custom<T: Copy>(items: &mut [T], less: impl Fn(&T, &T) -> bool) {
    let sorter = Sorter { less };
    let len = items.len();
    if len != 0 {
        sorter.introsort(items, 0, len, bitlog(len) * 2);
        sorter.final_insertion_sort(items, 0, len);
    }
}

fn bitlog(mut n: usize) -> usize {
    let mut k = 0;
    while n != 1 {
        n >>= 1;
        k += 1;
    }
    k
}

struct Sorter<F> {
    less: F,
}

impl<F> Sorter<F> {
    fn median_of_3_index<T>(&self, a: &[T], ai: usize, bi: usize, ci: usize) -> usize
    where
        F: Fn(&T, &T) -> bool,
    {
        let less = &self.less;
        let (x, y, z) = (&a[ai], &a[bi], &a[ci]);
        if less(x, y) {
            if less(y, z) {
                bi
            } else if less(x, z) {
                ci
            } else {
                ai
            }
        } else if less(x, z) {
            ai
        } else if less(y, z) {
            ci
        } else {
            bi
        }
    }

    fn push_heap<T: Copy>(&self, a: &mut [T], first: usize, mut hole: usize, top: usize, value: T)
    where
        F: Fn(&T, &T) -> bool,
    {
        let mut parent = hole.wrapping_sub(1) / 2;
        while hole > top && (self.less)(&a[first + parent], &value) {
            a[first + hole] = a[first + parent];
            hole = parent;
            parent = hole.wrapping_sub(1) / 2;
        }
        a[first + hole] = value;
    }

    fn pop_heap_to<T: Copy>(&self, a: &mut [T], first: usize, last: usize, result: usize, value: T)
    where
        F: Fn(&T, &T) -> bool,
    {
        a[result] = a[first];
        self.adjust_heap(a, first, 0, last - first, value);
    }

    fn pop_heap<T: Copy>(&self, a: &mut [T], first: usize, last: usize)
    where
        F: Fn(&T, &T) -> bool,
    {
        let value = a[last - 1];
        self.pop_heap_to(a, first, last - 1, last - 1, value);
    }

    fn adjust_heap<T: Copy>(&self, a: &mut [T], first: usize, mut hole: usize, len: usize, value: T)
    where
        F: Fn(&T, &T) -> bool,
    {
        let top = hole;
        let mut second_child = 2 * hole + 2;
        while second_child < len {
            if (self.less)(&a[first + second_child], &a[first + (second_child - 1)]) {
                second_child -= 1;
            }
            a[first + hole] = a[first + second_child];
            hole = second_child;
            second_child = 2 * (second_child + 1);
        }
        if second_child == len {
            a[first + hole] = a[first + (second_child - 1)];
            hole = second_child - 1;
        }
        self.push_heap(a, first, hole, top, value);
    }

    fn sort_heap<T: Copy>(&self, a: &mut [T], first: usize, mut last: usize)
    where
        F: Fn(&T, &T) -> bool,
    {
        while last - first > 1 {
            self.pop_heap(a, first, last);
            last -= 1;
        }
    }

    fn make_heap<T: Copy>(&self, a: &mut [T], first: usize, last: usize)
    where
        F: Fn(&T, &T) -> bool,
    {
        if last - first < 2 {
            return;
        }
        let len = last - first;
        let mut parent = (len - 2) / 2;
        loop {
            let value = a[first + parent];
            self.adjust_heap(a, first, parent, len, value);
            if parent == 0 {
                return;
            }
            parent -= 1;
        }
    }

    fn partial_sort<T: Copy>(&self, a: &mut [T], first: usize, last: usize, middle: usize)
    where
        F: Fn(&T, &T) -> bool,
    {
        self.make_heap(a, first, middle);
        for i in middle..last {
            if (self.less)(&a[i], &a[first]) {
                let value = a[i];
                self.pop_heap_to(a, first, middle, i, value);
            }
        }
        self.sort_heap(a, first, middle);
    }

    fn partitioner<T: Copy>(
        &self,
        a: &mut [T],
        mut first: usize,
        mut last: usize,
        pivot: usize,
    ) -> usize
    where
        F: Fn(&T, &T) -> bool,
    {
        // Where the pivot is, as it moves when swapped
        let mut at = pivot;
        loop {
            while first != pivot && (self.less)(&a[first], &a[at]) {
                first += 1;
            }
            last -= 1;
            while last != pivot && (self.less)(&a[at], &a[last]) {
                last -= 1;
            }
            if first >= last {
                return first;
            }
            if at == first {
                at = last;
            } else if at == last {
                at = first;
            }
            a.swap(first, last);
            first += 1;
        }
    }

    fn introsort<T: Copy>(&self, a: &mut [T], first: usize, mut last: usize, mut max_depth: usize)
    where
        F: Fn(&T, &T) -> bool,
    {
        while last - first > INTROSORT_THRESHOLD {
            if max_depth == 0 {
                self.partial_sort(a, first, last, last);
                return;
            }
            max_depth -= 1;
            let pivot = self.median_of_3_index(a, first, first + (last - first) / 2, last - 1);
            let cut = self.partitioner(a, first, last, pivot);
            self.introsort(a, cut, last, max_depth);
            last = cut;
        }
    }

    fn unguarded_linear_insert<T: Copy>(&self, a: &mut [T], mut last: usize, value: T)
    where
        F: Fn(&T, &T) -> bool,
    {
        let mut next = last - 1;
        while (self.less)(&value, &a[next]) {
            a[last] = a[next];
            last = next;
            next -= 1;
        }
        a[last] = value;
    }

    fn linear_insert<T: Copy>(&self, a: &mut [T], first: usize, last: usize)
    where
        F: Fn(&T, &T) -> bool,
    {
        let value = a[last];
        if (self.less)(&value, &a[first]) {
            a.copy_within(first..last, first + 1);
            a[first] = value;
        } else {
            self.unguarded_linear_insert(a, last, value);
        }
    }

    fn insertion_sort<T: Copy>(&self, a: &mut [T], first: usize, last: usize)
    where
        F: Fn(&T, &T) -> bool,
    {
        if first == last {
            return;
        }
        for i in first + 1..last {
            self.linear_insert(a, first, i);
        }
    }

    fn final_insertion_sort<T: Copy>(&self, a: &mut [T], first: usize, last: usize)
    where
        F: Fn(&T, &T) -> bool,
    {
        if last - first > INTROSORT_THRESHOLD {
            self.insertion_sort(a, first, first + INTROSORT_THRESHOLD);
            for i in first + INTROSORT_THRESHOLD..last {
                let value = a[i];
                self.unguarded_linear_insert(a, i, value);
            }
        } else {
            self.insertion_sort(a, first, last);
        }
    }
}
